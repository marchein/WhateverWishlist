import { TestBed } from '@angular/core/testing';
import { By } from '@angular/platform-browser';
import { ActionSheetController, AlertController, IonButton, IonModal, ModalController, NavController } from '@ionic/angular';
import { addIcons } from 'ionicons';
import { add, close, copyOutline, ellipsisVertical, eyeOffOutline, eyeOutline, giftOutline, shareSocialOutline } from 'ionicons/icons';
import { ApiService } from '../../core/api.service';
import type { WishlistWithItems } from '../../core/models';
import { NotifyService } from '../../core/ui';
import { WishlistDetailPage } from './wishlist-detail.page';

describe('Owner editing at the canonical share address', () => {
  const wishlist: WishlistWithItems = {
    id: 'list-id', title: 'Birthday', description: null, eventDate: null,
    shareToken: 'existing-token', createdAt: '', updatedAt: '', items: [],
  };
  const getWishlist = vi.fn();
  const regenerateShareToken = vi.fn();
  const navigateRoot = vi.fn();
  const modalCreate = vi.fn();
  const error = vi.fn();
  const systemShare = vi.fn();
  const writeText = vi.fn();

  beforeEach(() => {
    addIcons({ add, close, copyOutline, ellipsisVertical, eyeOffOutline, eyeOutline, giftOutline, shareSocialOutline });
    getWishlist.mockReset().mockResolvedValue(wishlist);
    regenerateShareToken.mockReset().mockResolvedValue({ ...wishlist, shareToken: 'new-token' });
    navigateRoot.mockReset();
    modalCreate.mockReset().mockResolvedValue({
      present: vi.fn(), onWillDismiss: async () => ({ role: 'saved' }),
    });
    error.mockReset();
    systemShare.mockReset().mockResolvedValue(undefined);
    writeText.mockReset().mockResolvedValue(undefined);
    vi.stubGlobal('navigator', {
      language: 'en',
      share: systemShare,
      clipboard: { writeText },
    });
    TestBed.configureTestingModule({
      imports: [WishlistDetailPage],
      providers: [
        { provide: ApiService, useValue: { getWishlist, regenerateShareToken } },
        { provide: NavController, useValue: { navigateRoot, navigateBack: vi.fn() } },
        { provide: NotifyService, useValue: { error, success: vi.fn() } },
        { provide: ModalController, useValue: { create: modalCreate } },
        {
          provide: ActionSheetController, useValue: {
            create: async () => ({ present: vi.fn(), onDidDismiss: async () => ({ data: 'regenerate' }) }),
          },
        },
        {
          provide: AlertController, useValue: {
            create: async () => ({ present: vi.fn(), onDidDismiss: async () => ({ role: 'confirm' }) }),
          },
        },
      ],
    });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  async function createEditor(renderTemplate = false) {
    if (!renderTemplate) {
      TestBed.overrideComponent(WishlistDetailPage, { set: { template: '', imports: [] } });
    }
    const fixture = TestBed.createComponent(WishlistDetailPage);
    fixture.componentRef.setInput('id', wishlist.id);
    fixture.detectChanges();
    await fixture.whenStable();
    fixture.detectChanges();
    return fixture;
  }

  it('loads the owner API on mount and refreshes when the parent revisits', async () => {
    const fixture = await createEditor();
    expect(getWishlist).toHaveBeenCalledWith(wishlist.id);
    fixture.componentRef.setInput('revision', 1);
    fixture.detectChanges();
    await fixture.whenStable();
    expect(getWishlist).toHaveBeenCalledTimes(2);
    expect(fixture.componentInstance.shareUrl()).toMatch(/\/s\/existing-token$/);
  });

  it('shows wish notes and orders wishes like the guest view', async () => {
    const item = (id: string, createdAt: string, priority: number, notes: string | null) => ({
      id, wishlistId: wishlist.id, title: id, notes, imageUrl: null, price: null, currency: null,
      priority, quantity: 1, links: [], createdAt, updatedAt: createdAt,
    });
    getWishlist.mockResolvedValue({
      ...wishlist,
      items: [item('old', '2026-01-01', 5, null), item('new', '2026-02-01', 1, 'Size M, blue')],
    });
    const fixture = await createEditor(true);
    const titles = () => [...fixture.nativeElement.querySelectorAll('ion-item h2')].map((el: Element) => el.textContent);
    expect(titles()).toEqual(['new', 'old']);
    expect(fixture.nativeElement.querySelector('ion-label p.notes')?.textContent).toContain('Size M, blue');
    fixture.componentInstance.setSort('priority');
    fixture.detectChanges();
    expect(titles()).toEqual(['old', 'new']);
  });

  it('requests the guest preview from the toolbar and the menu', async () => {
    const fixture = await createEditor(true);
    const previews = vi.fn();
    fixture.componentInstance.preview.subscribe(previews);
    const button = fixture.debugElement.queryAll(By.css('ion-header ion-button'))
      .find((element) => element.nativeElement.getAttribute('aria-label') === 'Preview as guest');
    button!.triggerEventHandler('click');
    expect(previews).toHaveBeenCalledTimes(1);
  });

  it('keeps item editing and refresh-after-save working', async () => {
    const fixture = await createEditor();
    await fixture.componentInstance.openEditor();
    expect(modalCreate).toHaveBeenCalledWith(expect.objectContaining({
      componentProps: { wishlistId: wishlist.id, item: undefined },
    }));
    expect(getWishlist).toHaveBeenCalledTimes(2);
  });

  it('moves to the new canonical address after explicitly regenerating a link', async () => {
    const fixture = await createEditor();
    expect(regenerateShareToken).not.toHaveBeenCalled();
    await fixture.componentInstance.openMenu();
    expect(regenerateShareToken).toHaveBeenCalledWith(wishlist.id);
    expect(navigateRoot).toHaveBeenCalledWith(['/s', 'new-token']);
  });

  it('opens the share dialog without immediately copying or invoking system sharing', async () => {
    const fixture = await createEditor();
    fixture.componentInstance.share();
    expect(fixture.componentInstance.sharing()).toBe(true);
    expect(writeText).not.toHaveBeenCalled();
    expect(systemShare).not.toHaveBeenCalled();
  });

  it('keeps sharing in the inline panel without a duplicate navigation-bar button', async () => {
    const fixture = await createEditor(true);
    const headerButtons = fixture.debugElement.queryAll(By.css('ion-header ion-button'));
    expect(headerButtons.map((element) => element.nativeElement.textContent.trim())).not.toContain('Share');
    const button = fixture.debugElement.queryAll(By.css('.share-panel ion-button'))
      .find((element) => element.nativeElement.textContent.trim() === 'Share');
    expect(button).toBeDefined();
    button!.triggerEventHandler('click');
    await fixture.whenStable();
    expect(fixture.componentInstance.sharing()).toBe(false);
    expect(writeText).not.toHaveBeenCalled();
    expect(systemShare).toHaveBeenCalledWith(expect.objectContaining({ url: fixture.componentInstance.shareUrl() }));
  });

  it('displays the canonical link inline with Copy and a supported system Share button', async () => {
    const fixture = await createEditor(true);
    const panel = fixture.nativeElement.querySelector('.share-panel');
    expect(panel).not.toBeNull();
    expect(panel.querySelector('ion-input').value).toBe(fixture.componentInstance.shareUrl());
    const buttons = fixture.debugElement.queryAll(By.css('.share-panel ion-button'));
    expect(buttons.map((button) => button.nativeElement.textContent.trim())).toEqual(['Copy link', 'Share']);
    buttons[0].triggerEventHandler('click');
    await fixture.whenStable();
    expect(writeText).toHaveBeenCalledWith(fixture.componentInstance.shareUrl());
    buttons[1].triggerEventHandler('click');
    await fixture.whenStable();
    expect(systemShare).toHaveBeenCalledWith(expect.objectContaining({ url: fixture.componentInstance.shareUrl() }));
  });

  it('keeps the inline link and Copy button but hides system Share when unsupported', async () => {
    vi.stubGlobal('navigator', { language: 'en', clipboard: { writeText } });
    const fixture = await createEditor(true);
    const panel = fixture.nativeElement.querySelector('.share-panel');
    expect(panel.querySelector('ion-input').value).toBe(fixture.componentInstance.shareUrl());
    expect(panel.querySelectorAll('ion-button')).toHaveLength(1);
    expect(panel.textContent).toContain('Copy link');
  });

  it('still opens the dialog on browsers without Web Share', async () => {
    vi.stubGlobal('navigator', { language: 'en', clipboard: { writeText } });
    const fixture = await createEditor();
    fixture.componentInstance.share();
    expect(fixture.componentInstance.sharing()).toBe(true);
    expect(fixture.componentInstance.systemSharingAvailable).toBe(false);
    expect(writeText).not.toHaveBeenCalled();
  });

  it('copies the existing canonical link only when explicitly requested', async () => {
    const fixture = await createEditor();
    fixture.componentInstance.share();
    await fixture.componentInstance.copyLink();
    expect(writeText).toHaveBeenCalledWith(fixture.componentInstance.shareUrl());
    expect(fixture.componentInstance.shareUrl()).toMatch(/\/s\/existing-token$/);
    expect(fixture.componentInstance.sharing()).toBe(true);
  });

  it('shares the same URL using the system when requested', async () => {
    const fixture = await createEditor();
    await fixture.componentInstance.shareUsingDevice();
    expect(systemShare).toHaveBeenCalledWith(expect.objectContaining({
      title: wishlist.title, url: fixture.componentInstance.shareUrl(),
    }));
    expect(writeText).not.toHaveBeenCalled();
  });

  it('keeps the dialog open on cancellation without copying or reporting an error', async () => {
    systemShare.mockRejectedValue(new DOMException('Canceled', 'AbortError'));
    const fixture = await createEditor();
    fixture.componentInstance.share();
    await fixture.componentInstance.shareUsingDevice();
    expect(fixture.componentInstance.sharing()).toBe(true);
    expect(error).not.toHaveBeenCalled();
    expect(writeText).not.toHaveBeenCalled();
  });

  it('reports real sharing errors and leaves manual copying available', async () => {
    const failure = new Error('Permission denied');
    systemShare.mockRejectedValue(failure);
    const fixture = await createEditor();
    fixture.componentInstance.share();
    await fixture.componentInstance.shareUsingDevice();
    expect(error).toHaveBeenCalledWith(failure);
    expect(fixture.componentInstance.sharing()).toBe(true);
    expect(writeText).not.toHaveBeenCalled();
  });

  it('reports copying failures while keeping the link available for manual copying', async () => {
    writeText.mockRejectedValue(new Error('Clipboard unavailable'));
    const fixture = await createEditor();
    fixture.componentInstance.share();
    await fixture.componentInstance.copyLink();
    expect(error).toHaveBeenCalled();
    expect(fixture.componentInstance.sharing()).toBe(true);
  });
});
