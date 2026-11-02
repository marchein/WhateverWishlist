import { Component, input } from '@angular/core';
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
}

describe('Shared wishlist owner and recipient views', () => {
  const getShared = vi.fn();
  const error = vi.fn();
  const response = (isOwner: boolean): SharedWishlist => ({
    wishlist: {
      id: 'list-id', title: 'Birthday', description: null, eventDate: null, ownerName: 'Owner',
    },
    isOwner,
    items: [],
  });

  beforeEach(() => {
    getShared.mockReset();
    error.mockReset();
    TestBed.configureTestingModule({
      imports: [SharedWishlistPage],
      providers: [
        provideRouter([]),
        { provide: ApiService, useValue: { getShared } },
        { provide: AuthService, useValue: { isLoggedIn: () => false } },
        { provide: NotifyService, useValue: { error } },
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
});
