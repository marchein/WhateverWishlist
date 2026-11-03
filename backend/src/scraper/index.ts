import { extractFromHtml, extractUrl, guessTitleFromUrl, type ScrapeSource } from './extract.js';
import { fetchPage, ScrapeError, type FetchedPage, type ScrapeErrorCode } from './safe-fetch.js';
import { imageCache } from '../services/image-cache.js';

export type ScrapeMessageCode =
  | ScrapeErrorCode
  | 'NO_LINK_FOUND'
  | 'TIMEOUT'
  | 'DNS_NOT_FOUND'
  | 'CONNECTION_REFUSED'
  | 'TLS_ERROR'
  | 'FETCH_FAILED'
  | 'BLOCKED_HTTP'
  | 'HTTP_ERROR'
  | 'ROBOT_CHECK'
  | 'NOT_A_WEB_PAGE'
  | 'TITLE_GUESSED';

/** Explains what went wrong or was guessed. Clients translate `code`; `message` is an English fallback. */
export interface ScrapeMessage {
  code: ScrapeMessageCode;
  params?: Record<string, string | number>;
  message: string;
}

export interface ScrapeResult {
  /** Exactly what the user pasted. */
  input: string;
  /** The link found in the input (null if there was none). */
  url: string | null;
  /** Where we ended up after following redirects (e.g. short links). */
  finalUrl: string | null;
  /** ok = title, image and price found on the page; partial = some; failed = nothing from the page. */
  status: 'ok' | 'partial' | 'failed';
  title: string | null;
  image: string | null;
  price: number | null;
  currency: string | null;
  siteName: string | null;
  sources: { title?: ScrapeSource; image?: ScrapeSource; price?: ScrapeSource };
  messages: ScrapeMessage[];
}

const msg = (code: ScrapeMessageCode, message: string, params?: ScrapeMessage['params']): ScrapeMessage => ({
  code,
  message,
  ...(params && { params }),
});

function describeFetchError(error: unknown): ScrapeMessage {
  const cause = (error as { cause?: unknown })?.cause;
  if (error instanceof ScrapeError) return msg(error.code, error.message);
  if (cause instanceof ScrapeError) return msg(cause.code, cause.message);
  const name = (error as Error)?.name;
  if (name === 'TimeoutError' || name === 'AbortError') return msg('TIMEOUT', 'The website took too long to respond.');
  const code = (cause as { code?: string })?.code;
  if (code === 'ENOTFOUND' || code === 'EAI_AGAIN') {
    return msg('DNS_NOT_FOUND', "The website's address couldn't be found – is the link correct?");
  }
  if (code === 'ECONNREFUSED' || code === 'ECONNRESET') return msg('CONNECTION_REFUSED', 'The website refused the connection.');
  if (code?.startsWith('CERT_') || code?.includes('SSL')) return msg('TLS_ERROR', "The website's security certificate is invalid.");
  return msg('FETCH_FAILED', 'The website could not be loaded.');
}

export async function scrape(input: string, acceptLanguage: string): Promise<ScrapeResult> {
  const result: ScrapeResult = {
    input,
    url: null,
    finalUrl: null,
    status: 'failed',
    title: null,
    image: null,
    price: null,
    currency: null,
    siteName: null,
    sources: {},
    messages: [],
  };

  const url = extractUrl(input);
  if (!url) {
    result.title = input.slice(0, 300);
    result.sources.title = 'pasted-text';
    result.messages.push(
      msg('NO_LINK_FOUND', "We couldn't find a link in what you pasted, so we used the text as the title."),
    );
    return result;
  }
  result.url = url;
  // Text around the link (e.g. from a share sheet) is often the product name.
  const surroundingText = input.replace(url, ' ').replace(/\s+/g, ' ').trim() || undefined;

  let page: FetchedPage | undefined;
  try {
    page = await fetchPage(url, acceptLanguage);
    result.finalUrl = page.finalUrl;
  } catch (error) {
    result.messages.push(describeFetchError(error));
  }

  let foundOnPage = 0;
  if (page) {
    if (page.status >= 400) {
      const params = { status: page.status };
      result.messages.push(
        page.status === 403 || page.status === 429 || page.status === 503
          ? msg('BLOCKED_HTTP', `The shop blocked our request (HTTP ${page.status}). Please fill in the details yourself.`, params)
          : msg('HTTP_ERROR', `The website answered with an error (HTTP ${page.status}).`, params),
      );
    } else if (page.contentType.startsWith('image/')) {
      result.image = await imageCache.cacheImage(page.finalUrl);
      result.sources.image = 'link-itself';
      foundOnPage++;
    } else if (page.html) {
      const extracted = extractFromHtml(page.html, page.finalUrl);
      if (extracted.blocked) {
        result.messages.push(
          msg('ROBOT_CHECK', 'The shop showed a robot check instead of the product page, so we could not read the details.'),
        );
      } else {
        result.title = extracted.title ?? null;
        result.image = extracted.image ? await imageCache.cacheImage(extracted.image) : null;
        result.price = extracted.price ?? null;
        result.currency = extracted.currency ?? null;
        result.siteName = extracted.siteName ?? null;
        result.sources = { ...extracted.sources };
        foundOnPage = [result.title, result.image, result.price].filter((v) => v !== null).length;
      }
    } else {
      const contentType = page.contentType || 'unknown type';
      result.messages.push(
        msg('NOT_A_WEB_PAGE', `The link doesn't point to a web page (${contentType}).`, { contentType }),
      );
    }
  }

  const effectiveUrl = new URL(result.finalUrl ?? url);
  result.siteName ??= effectiveUrl.hostname.replace(/^www\./, '');
  if (!result.title && surroundingText) {
    result.title = surroundingText.slice(0, 300);
    result.sources.title = 'pasted-text';
  }
  if (!result.title) {
    const guessed = guessTitleFromUrl(effectiveUrl) ?? guessTitleFromUrl(new URL(url));
    if (guessed) {
      result.title = guessed;
      result.sources.title = 'link-address';
      result.messages.push(msg('TITLE_GUESSED', 'The title was guessed from the link address – please check it.'));
    }
  }

  result.status = foundOnPage === 3 ? 'ok' : foundOnPage > 0 ? 'partial' : 'failed';
  return result;
}
