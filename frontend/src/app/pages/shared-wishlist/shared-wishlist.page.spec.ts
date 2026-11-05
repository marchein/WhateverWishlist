import { Component, input, model, output } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { ApiService } from '../../core/api.service';
import { AuthService } from '../../core/auth.service';
import type { SharedWishlist } from '../../core/models';
import { NotifyService } from '../../core/ui';
import { WishlistDetailPage } from '../wishlist-detail/wishlist-detail.page';
import { SharedWishlistPage } from './shared-wishlist.page';

@Component({
  selector: 'app-wishlist-detail',
  template: '<button>Edit wishlist {{ id() }}</button>',
})
class OwnerEditorStubComponent {
  readonly id = input.required<string>();
  readonly revision = input(0);
  readonly sort = model('newest');
  readonly preview = output<void>();
}

describe('Shared wishlist owner and recipient views', () => {
  const getShared = vi.fn();
  const followWishlist = vi.fn();
  const unfollowWishlist = vi.fn();
  const error = vi.fn();
  const success = vi.fn();
  let loggedIn = false;
  const response = (isOwner: boolean): SharedWishlist => ({
    wishlist: {
      id: 'list-id', title: 'Birthday', description: null, eventDate: null, ownerName: 'Owner',
    },
    isOwner,
    items: [],
  });

  beforeEach(() => {
    getShared.mockReset();
    followWishlist.mockReset().mockResolvedValue({ isFollowing: true });
    unfollowWishlist.mockReset().mockResolvedValue({ isFollowing: false });
    error.mockReset();
    success.mockReset();
    loggedIn = false;
    TestBed.configureTestingModule({
      imports: [SharedWishlistPage],
      providers: [
        provideRouter([]),
        { provide: ApiService, useValue: { getShared, followWishlist, unfollowWishlist } },
        { provide: AuthService, useValue: { isLoggedIn: () => loggedIn } },
        { provide: NotifyService, useValue: { error, success } },
      ],
    }).overrideComponent(SharedWishlistPage, {
      remove: { imports: [WishlistDetailPage] },
      add: { imports: [OwnerEditorStubComponent] },
    });
  });

  it('renders editing controls only when the API confirms ownership', async () => {
    getShared.mockResolvedValue(response(true));
    const fixture = TestBed.createComponent(SharedWishlistPage);
    fixture.componentRef.setInput('token', 'existing-token');
    await fixture.componentInstance.load();
    fixture.detectChanges();
    expect(getShared).toHaveBeenCalledWith('existing-token');
    expect(fixture.nativeElement.querySelector('app-wishlist-detail')?.textContent).toContain('list-id');
    expect(fixture.nativeElement.querySelector('ion-segment')).toBeNull();
  });

  it('lets the owner preview the guest layout without purchase controls', async () => {
    getShared.mockResolvedValue(response(true));
    const fixture = TestBed.createComponent(SharedWishlistPage);
    fixture.componentRef.setInput('token', 'existing-token');
    await fixture.componentInstance.load();
    fixture.detectChanges();
    const added = { ...response(true), items: [{
      id: 'new-item', wishlistId: 'list-id', title: 'Added meanwhile', notes: null, imageUrl: null, displayImageUrl: null, price: null,
      currency: null, priority: 3, quantity: 1, links: [], createdAt: '2026-01-01', updatedAt: '2026-01-01',
    }] };
    getShared.mockResolvedValue(added);
    await fixture.componentInstance.startPreview();
    fixture.detectChanges();
    expect(getShared).toHaveBeenCalledTimes(2);
    expect(fixture.nativeElement.textContent).toContain('Added meanwhile');
    expect(fixture.nativeElement.querySelector('app-wishlist-detail')).toBeNull();
    expect(fixture.nativeElement.querySelector('.owner-note')).not.toBeNull();
    expect(fixture.nativeElement.querySelector('ion-accordion-group')).toBeNull();
    fixture.componentInstance.previewing.set(false);
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('app-wishlist-detail')).not.toBeNull();
  });

  it('renders the recipient view without editing controls for a non-owner', async () => {
    getShared.mockResolvedValue(response(false));
    const fixture = TestBed.createComponent(SharedWishlistPage);
    fixture.componentRef.setInput('token', 'existing-token');
    await fixture.componentInstance.load();
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('app-wishlist-detail')).toBeNull();
    expect(fixture.nativeElement.querySelector('ion-segment')).not.toBeNull();
  });

  it('refreshes owner content when revisiting and removes it if access is lost', async () => {
    getShared.mockResolvedValue(response(true));
    const fixture = TestBed.createComponent(SharedWishlistPage);
    fixture.componentRef.setInput('token', 'existing-token');
    await fixture.componentInstance.load();
    const revision = fixture.componentInstance.revision();
    await fixture.componentInstance.load();
    expect(fixture.componentInstance.revision()).toBeGreaterThan(revision);
    const failure = new Error('Link revoked');
    getShared.mockRejectedValue(failure);
    await fixture.componentInstance.load();
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('app-wishlist-detail')).toBeNull();
    expect(error).toHaveBeenCalledWith(failure);
  });

  it('lets logged-in recipients follow and unfollow the list', async () => {
    loggedIn = true;
    getShared.mockResolvedValue({ ...response(false), isFollowing: false });
    const fixture = TestBed.createComponent(SharedWishlistPage);
    fixture.componentRef.setInput('token', 'existing-token');
    await fixture.componentInstance.load();
    fixture.detectChanges();
    const button = () => fixture.nativeElement.querySelector('ion-button.follow') as HTMLElement;
    expect(button().getAttribute('aria-pressed')).toBe('false');

    await fixture.componentInstance.toggleFollow();
    fixture.detectChanges();
    expect(followWishlist).toHaveBeenCalledWith('existing-token');
    expect(success).toHaveBeenCalledTimes(1);
    expect(button().getAttribute('aria-pressed')).toBe('true');

    await fixture.componentInstance.toggleFollow();
    fixture.detectChanges();
    expect(unfollowWishlist).toHaveBeenCalledWith('existing-token');
    expect(button().getAttribute('aria-pressed')).toBe('false');
  });

  it('offers following neither to guests nor to the owner', async () => {
    getShared.mockResolvedValue(response(false));
    const fixture = TestBed.createComponent(SharedWishlistPage);
    fixture.componentRef.setInput('token', 'existing-token');
    await fixture.componentInstance.load();
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('ion-button.follow')).toBeNull();

    loggedIn = true;
    getShared.mockResolvedValue(response(true));
    await fixture.componentInstance.startPreview();
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('.owner-note')).not.toBeNull();
    expect(fixture.nativeElement.querySelector('ion-button.follow')).toBeNull();
    await fixture.componentInstance.toggleFollow();
    expect(followWishlist).not.toHaveBeenCalled();
  });
});
