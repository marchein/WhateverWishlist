export interface User {
  id: string;
  email: string;
  displayName: string;
}

export interface AuthResponse {
  token: string;
  user: User;
}

export interface Wishlist {
  id: string;
  title: string;
  description: string | null;
  eventDate: string | null;
  shareToken: string;
  itemCount?: number;
  createdAt: string;
  updatedAt: string;
}

export type WishlistInput = Pick<Wishlist, 'title' | 'description' | 'eventDate'>;

/** Someone else's list the user follows via its share link. */
export interface FollowedWishlist extends Wishlist {
  ownerName: string;
  followedAt: string;
}

export interface Item {
  id: string;
  wishlistId: string;
  title: string;
  notes: string | null;
  imageUrl: string | null;
  price: number | null;
  currency: string | null;
  priority: number;
  quantity: number;
  links: string[];
  createdAt: string;
  updatedAt: string;
}

export type ItemInput = Pick<Item, 'title' | 'notes' | 'imageUrl' | 'price' | 'currency' | 'priority' | 'quantity' | 'links'>;

export interface WishlistWithItems extends Wishlist {
  /** Owner view only: how many people follow the list through its share link. */
  followerCount?: number;
  items: Item[];
}

export interface Follower {
  userId: string;
  displayName: string;
  followedAt: string;
}

export interface Purchase {
  id: string;
  quantity: number;
  buyerName: string;
  createdAt: string;
  revertedAt: string | null;
  revertedByName: string | null;
  isMine: boolean;
}

/** Purchase fields are absent when the viewer is the owner of the list. */
export interface SharedItem extends Item {
  purchasedQuantity?: number;
  purchases?: Purchase[];
}

export interface SharedWishlist {
  wishlist: {
    id: string;
    title: string;
    description: string | null;
    eventDate: string | null;
    ownerName: string;
  };
  isOwner: boolean;
  isFollowing?: boolean;
  items: SharedItem[];
}

export type ScrapeSource =
  | 'structured-data'
  | 'product-page'
  | 'preview-tags'
  | 'product-markup'
  | 'page-title'
  | 'page'
  | 'link-address'
  | 'pasted-text'
  | 'link-itself';

export interface ScrapeMessage {
  code: string;
  params?: Record<string, string | number>;
  /** English fallback for codes the app doesn't know yet. */
  message: string;
}

export interface ScrapeResult {
  input: string;
  url: string | null;
  finalUrl: string | null;
  status: 'ok' | 'partial' | 'failed';
  title: string | null;
  image: string | null;
  price: number | null;
  currency: string | null;
  siteName: string | null;
  sources: { title?: ScrapeSource; image?: ScrapeSource; price?: ScrapeSource };
  messages: ScrapeMessage[];
}
