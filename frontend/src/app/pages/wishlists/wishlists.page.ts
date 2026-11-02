import { Component, inject, signal, viewChild } from '@angular/core';
import { FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { RouterLink } from '@angular/router';
import {
  IonButton,
  IonButtons,
  IonContent,
  IonFab,
  IonFabButton,
  IonHeader,
  IonIcon,
  IonItem,
  IonLabel,
  IonList,
  IonModal,
  IonRefresher,
  IonRefresherContent,
  IonRouterLink,
  IonSpinner,
  IonTitle,
  IonToolbar,
  NavController,
  type RefresherCustomEvent,
  type ViewWillEnter,
} from '@ionic/angular';
import { ApiService } from '../../core/api.service';
import { LanguageSwitchComponent } from '../../components/language-switch.component';
import { AuthService } from '../../core/auth.service';
import { I18nService, LocalDatePipe, TranslatePipe } from '../../core/i18n/i18n';
import type { Wishlist } from '../../core/models';
import { NotifyService } from '../../core/ui';

@Component({
  selector: 'app-wishlists',
  templateUrl: 'wishlists.page.html',
  styleUrls: ['wishlists.page.scss'],
  imports: [
    ReactiveFormsModule,
    LanguageSwitchComponent,
    LocalDatePipe,
    TranslatePipe,
    RouterLink,
    IonRouterLink,
    IonHeader,
    IonToolbar,
    IonTitle,
    IonButtons,
    IonButton,
    IonIcon,
    IonContent,
    IonRefresher,
    IonRefresherContent,
    IonList,
    IonModal,
    IonItem,
    IonLabel,
    IonSpinner,
    IonFab,
    IonFabButton,
  ],
})
export class WishlistsPage implements ViewWillEnter {
  private readonly api = inject(ApiService);
  private readonly nav = inject(NavController);
  private readonly notify = inject(NotifyService);
  protected readonly auth = inject(AuthService);
  private readonly i18n = inject(I18nService);
  private readonly createModal = viewChild.required(IonModal);

  readonly wishlists = signal<Wishlist[]>([]);
  readonly loading = signal(true);
  readonly creating = signal(false);
  readonly saving = signal(false);
  readonly canDismissCreation = async (_data?: unknown, role?: string): Promise<boolean> =>
    role === 'confirm' || !this.saving();
  readonly form = new FormGroup({
    title: new FormControl('', {
      nonNullable: true,
      validators: [Validators.required, Validators.maxLength(120), Validators.pattern(/\S/)],
    }),
    eventDate: new FormControl('', { nonNullable: true }),
  });

  ionViewWillEnter(): void {
    void this.load();
  }

  async load(event?: RefresherCustomEvent): Promise<void> {
    try {
      this.wishlists.set(await this.api.listWishlists());
    } catch (error) {
      await this.notify.error(error);
    } finally {
      this.loading.set(false);
      await event?.target.complete();
    }
  }

  create(): void {
    this.form.reset();
    this.creating.set(true);
  }

  async submit(): Promise<void> {
    if (this.saving()) return;
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      await this.notify.error(this.i18n.t('wishlists.titleRequired'));
      return;
    }

    const { title, eventDate } = this.form.getRawValue();
    this.saving.set(true);
    try {
      const wishlist = await this.api.createWishlist({
        title: title.trim(),
        description: null,
        eventDate: eventDate || null,
      });
      await this.createModal().dismiss(undefined, 'confirm');
      this.creating.set(false);
      await this.nav.navigateForward(['/s', wishlist.shareToken]);
    } catch (error) {
      await this.notify.error(error);
    } finally {
      this.saving.set(false);
    }
  }

  async logout(): Promise<void> {
    this.auth.logout();
    await this.nav.navigateRoot('/login');
  }
}
