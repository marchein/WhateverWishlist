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
  const listFollowers = vi.fn();
  const removeFollower = vi.fn();
  const alertCreate = vi.fn();
  const alertDismiss = vi.fn();
  const menuChoice = vi.fn();
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
    listFollowers.mockReset().mockResolvedValue([
      { userId: 'fred', displayName: 'Fred', followedAt: '2026-02-01T10:00:00.000Z' },
      { userId: 'gina', displayName: 'Gina', followedAt: '2026-02-02T10:00:00.000Z' },
    ]);
    removeFollower.mockReset().mockResolvedValue(undefined);
    alertDismiss.mockReset().mockResolvedValue({ role: 'confirm' });
    alertCreate.mockReset().mockImplementation(async () => ({ present: vi.fn(), onDidDismiss: alertDismiss }));
    menuChoice.mockReset().mockReturnValue('regenerate');
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
        { provide: ApiService, useValue: { getWishlist, regenerateShareToken, listFollowers, removeFollower } },
        { provide: NavController, useValue: { navigateRoot, navigateBack: vi.fn() } },
        { provide: NotifyService, useValue: { error, success: vi.fn() } },
        { provide: ModalController, useValue: { create: modalCreate } },
        {
          provide: ActionSheetController, useValue: {
            create: async () => ({ present: vi.fn(), onDidDismiss: async () => ({ data: menuChoice() }) }),
          },
        },
        {
          provide: AlertController, useValue: { create: alertCreate },
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
    const titles = () => [...fixture.nativeElement.querySelectorAll('ion-item h3')].map((el: Element) => el.textContent);
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

  it('opens the regenerate dialog with followers kept by default and moves to the new address', async () => {
    const fixture = await createEditor();
    const page = fixture.componentInstance;
    page.keepFollowers.set(false);
    await page.openMenu();
    expect(page.regenerating()).toBe(true);
    expect(page.keepFollowers()).toBe(true);
    expect(regenerateShareToken).not.toHaveBeenCalled();

    await page.confirmRegenerate();
    expect(regenerateShareToken).toHaveBeenCalledWith(wishlist.id, true);
    expect(navigateRoot).toHaveBeenCalledWith(['/s', 'new-token']);
    expect(page.regenerating()).toBe(false);
  });

  it('removes followers when the toggle is switched off and explains the consequence', async () => {
    getWishlist.mockResolvedValue({ ...wishlist, followerCount: 2 });
    const fixture = await createEditor(true);
    const page = fixture.componentInstance;
    page.regenerateLink();
    fixture.detectChanges();
    const modal = fixture.debugElement.queryAll(By.directive(IonModal))
      .map((element) => element.componentInstance as IonModal)
      .find((instance) => (instance as unknown as { el: HTMLElement }).el.classList.contains('regenerate-dialog'))!;
    await modal.present();
    fixture.detectChanges();
    const hint = () => document.querySelector('#keep-followers-hint')?.textContent ?? '';
    expect(document.querySelector('ion-toggle.keep-followers')?.textContent).toContain('Keep followers');
    expect(document.querySelector('ion-toggle.keep-followers')?.textContent).toContain('2 followers');
    expect(hint()).toContain('automatically use the new link');

    page.keepFollowers.set(false);
    fixture.detectChanges();
    expect(hint()).toContain('All current followers are removed');
    await page.confirmRegenerate();
    expect(regenerateShareToken).toHaveBeenCalledWith(wishlist.id, false);
    await modal.dismiss();
  });

  it('keeps the dialog open and reports errors when regenerating fails', async () => {
    const failure = new Error('Offline');
    regenerateShareToken.mockRejectedValue(failure);
    const page = (await createEditor()).componentInstance;
    page.regenerateLink();
    await page.confirmRegenerate();
    expect(error).toHaveBeenCalledWith(failure);
    expect(page.regenerating()).toBe(true);
    expect(page.regenerateBusy()).toBe(false);
    expect(navigateRoot).not.toHaveBeenCalled();
  });

  it('shows followers and removes one after confirmation', async () => {
    getWishlist.mockResolvedValue({ ...wishlist, followerCount: 2 });
    const fixture = await createEditor(true);
    const page = fixture.componentInstance;
    expect(fixture.nativeElement.querySelector('.followers-button')?.textContent).toContain('2 followers');

    menuChoice.mockReturnValue('followers');
    await page.openMenu();
    expect(listFollowers).toHaveBeenCalledWith(wishlist.id);
    expect(page.showingFollowers()).toBe(true);
    expect(page.followers()?.map((follower) => follower.displayName)).toEqual(['Fred', 'Gina']);

    alertDismiss.mockResolvedValue({ role: 'cancel' });
    await page.removeFollower(page.followers()![0]!);
    expect(removeFollower).not.toHaveBeenCalled();

    alertDismiss.mockResolvedValue({ role: 'destructive' });
    await page.removeFollower(page.followers()![0]!);
    expect(removeFollower).toHaveBeenCalledWith(wishlist.id, 'fred');
    expect(page.followers()?.map((follower) => follower.displayName)).toEqual(['Gina']);
    expect(page.wishlist()?.followerCount).toBe(1);
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('.followers-button')?.textContent).toContain('1 follower');
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
