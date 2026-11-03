import { TestBed } from '@angular/core/testing';
import { By } from '@angular/platform-browser';
import { provideRouter } from '@angular/router';
import { IonModal, NavController } from '@ionic/angular';
import { ApiService } from '../../core/api.service';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n/i18n';
import { NotifyService } from '../../core/ui';
import { WishlistsPage } from './wishlists.page';

describe('Wishlist overview sections', () => {
  const listWishlists = vi.fn();
  const listFollowedWishlists = vi.fn();
  const unfollowWishlist = vi.fn();
  const success = vi.fn();
  const error = vi.fn();
  const list = (id: string, title: string) => ({
    id, title, description: null, eventDate: null, shareToken: `${id}-token`, itemCount: 2,
    createdAt: '2026-01-01', updatedAt: '2026-01-01',
  });

  beforeEach(() => {
    listWishlists.mockReset().mockResolvedValue([list('own', 'Birthday')]);
    listFollowedWishlists.mockReset().mockResolvedValue([
      { ...list('friend', 'Christmas'), ownerName: 'Olivia', followedAt: '2026-02-01' },
    ]);
    unfollowWishlist.mockReset().mockResolvedValue({ isFollowing: false });
    success.mockReset();
    error.mockReset();
    TestBed.configureTestingModule({
      imports: [WishlistsPage],
      providers: [
        provideRouter([]),
        { provide: ApiService, useValue: { listWishlists, listFollowedWishlists, unfollowWishlist } },
        { provide: AuthService, useValue: { user: () => ({ displayName: 'Fred' }) } },
        { provide: NavController, useValue: {} },
        { provide: NotifyService, useValue: { error, success } },
      ],
    });
    TestBed.inject(I18nService).setLanguage('en');
  });

  afterEach(() => {
    localStorage.removeItem('wishlist.language');
  });

  async function loadPage() {
    const fixture = TestBed.createComponent(WishlistsPage);
    await fixture.componentInstance.load();
    fixture.detectChanges();
    return fixture;
  }

  it('shows the app name and separate sections for own and followed lists', async () => {
    const fixture = await loadPage();
    const element = fixture.nativeElement as HTMLElement;
    expect(element.querySelector('ion-title')?.textContent).toContain('WhateverWishlist');
    expect(element.querySelector('.greeting')?.textContent).toContain('Hi Fred!');
    const headers = [...element.querySelectorAll('section h2')].map((header) => header.textContent?.trim());
    expect(headers).toEqual(['My wishlists', 'Followed wishlists']);
    expect(element.querySelector('section.own ion-list')?.textContent).toContain('Birthday');
    expect(element.querySelector('section.followed .followed-tile')?.textContent?.trim()).toBe('O');
    const followed = element.querySelector('section.followed ion-list')?.textContent ?? '';
    expect(followed).toContain('Christmas');
    expect(followed).toContain('by Olivia');
  });

  it('keeps the followed section visible when the user has no own lists yet', async () => {
    listWishlists.mockResolvedValue([]);
    const fixture = await loadPage();
    const element = fixture.nativeElement as HTMLElement;
    expect(element.querySelector('.empty')).toBeNull();
    const createButton = element.querySelector<HTMLButtonElement>('section.own button.placeholder');
    expect(createButton?.textContent).toContain('Create my first wishlist');
    createButton?.click();
    expect(fixture.componentInstance.creating()).toBe(true);
    expect(element.querySelector('section.followed ion-list')?.textContent).toContain('Christmas');
  });

  it('shows the welcome screen when there is nothing to list at all', async () => {
    listWishlists.mockResolvedValue([]);
    listFollowedWishlists.mockResolvedValue([]);
    const element = (await loadPage()).nativeElement as HTMLElement;
    expect(element.querySelector('.empty')?.textContent).toContain('Hi Fred!');
    expect(element.querySelector('ion-list')).toBeNull();
  });

  it('removes a list from the followed section after unfollowing', async () => {
    const fixture = await loadPage();
    const page = fixture.componentInstance;
    await page.unfollow(page.followed()[0]!);
    fixture.detectChanges();
    expect(unfollowWishlist).toHaveBeenCalledWith('friend-token');
    expect(page.followed()).toEqual([]);
    expect(success).toHaveBeenCalledTimes(1);
    expect((fixture.nativeElement as HTMLElement).querySelector('section.followed .placeholder')?.textContent).toContain(
      'Open a wishlist someone sent you',
    );
  });
});

describe('Wishlist creation form', () => {
  const createWishlist = vi.fn();
  const navigateForward = vi.fn();
  const error = vi.fn();

  beforeEach(() => {
    createWishlist.mockReset().mockResolvedValue({ shareToken: 'new-token' });
    navigateForward.mockReset();
    error.mockReset();
    TestBed.configureTestingModule({
      imports: [WishlistsPage],
      providers: [
        provideRouter([]),
        { provide: ApiService, useValue: { createWishlist } },
        { provide: AuthService, useValue: { user: () => null } },
        { provide: NavController, useValue: { navigateForward } },
        { provide: NotifyService, useValue: { error } },
      ],
    });
    TestBed.inject(I18nService).setLanguage('en');
  });

  afterEach(() => {
    localStorage.removeItem('wishlist.language');
  });

  function createPage() {
    const fixture = TestBed.createComponent(WishlistsPage);
    fixture.detectChanges();
    return fixture;
  }

  it('renders persistent labels for both fields, including the native date input', async () => {
    const fixture = createPage();
    fixture.componentInstance.create();
    fixture.detectChanges();
    const modal = fixture.debugElement.query(By.directive(IonModal)).componentInstance as IonModal;
    await modal.present();
    fixture.detectChanges();
    const title = document.querySelector<HTMLLabelElement>('label[for="wishlist-title"]');
    const date = document.querySelector<HTMLLabelElement>('label[for="wishlist-date"]');
    expect(title?.textContent).toBe('Title');
    expect(date?.textContent).toBe('Date (optional)');
    expect(date?.control?.getAttribute('type')).toBe('date');
    expect(document.querySelector('ion-alert')).toBeNull();
    await modal.dismiss();
  });

  it('creates a list with a trimmed title and an optional date, then navigates to it', async () => {
    const fixture = createPage();
    const page = fixture.componentInstance;
    page.create();
    fixture.detectChanges();
    const modal = fixture.debugElement.query(By.directive(IonModal)).componentInstance as IonModal;
    await modal.present();
    const dismiss = vi.spyOn(modal, 'dismiss');
    navigateForward.mockImplementationOnce(() => {
      expect(document.querySelector('ion-modal.show-modal')).toBeNull();
    });
    page.form.setValue({ title: '  Birthday  ', eventDate: '2027-01-06' });
    await page.submit();
    expect(createWishlist).toHaveBeenCalledWith({
      title: 'Birthday', description: null, eventDate: '2027-01-06',
    });
    expect(navigateForward).toHaveBeenCalledWith(['/s', 'new-token']);
    expect(dismiss).toHaveBeenCalledWith(undefined, 'confirm');
    expect(page.creating()).toBe(false);
    expect(page.saving()).toBe(false);
  });

  it('sends null for an omitted date and resets fields when opening a new form', async () => {
    const page = createPage().componentInstance;
    page.create();
    page.form.controls.title.setValue('Christmas');
    await page.submit();
    expect(createWishlist).toHaveBeenCalledWith({
      title: 'Christmas', description: null, eventDate: null,
    });
    page.create();
    expect(page.form.getRawValue()).toEqual({ title: '', eventDate: '' });
  });

  it('rejects whitespace-only and overlong titles with an explicit error', async () => {
    const page = createPage().componentInstance;
    for (const title of ['   ', 'x'.repeat(121)]) {
      page.form.controls.title.setValue(title);
      await page.submit();
    }
    expect(createWishlist).not.toHaveBeenCalled();
    expect(error).toHaveBeenCalledTimes(2);
  });

  it('keeps entered values and the form open after an API failure', async () => {
    const failure = new Error('Offline');
    createWishlist.mockRejectedValue(failure);
    const page = createPage().componentInstance;
    page.create();
    page.form.controls.title.setValue('Birthday');
    await page.submit();
    expect(error).toHaveBeenCalledWith(failure);
    expect(page.creating()).toBe(true);
    expect(page.form.controls.title.value).toBe('Birthday');
    expect(page.saving()).toBe(false);
    expect(navigateForward).not.toHaveBeenCalled();
  });

  it('prevents duplicate submissions while saving', async () => {
    let finish!: (value: { shareToken: string }) => void;
    createWishlist.mockReturnValue(new Promise<{ shareToken: string }>((resolve) => { finish = resolve; }));
    const page = createPage().componentInstance;
    page.create();
    page.form.controls.title.setValue('Birthday');
    const submission = page.submit();
    await page.submit();
    expect(createWishlist).toHaveBeenCalledTimes(1);
    expect(page.saving()).toBe(true);
    expect(await page.canDismissCreation()).toBe(false);
    expect(await page.canDismissCreation(undefined, 'confirm')).toBe(true);
    finish({ shareToken: 'new-token' });
    await submission;
    expect(page.saving()).toBe(false);
  });
});
