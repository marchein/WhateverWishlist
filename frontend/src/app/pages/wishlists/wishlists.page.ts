import { Component, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import {
  AlertController,
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
    IonItem,
    IonLabel,
    IonSpinner,
    IonFab,
    IonFabButton,
  ],
})
export class WishlistsPage implements ViewWillEnter {
  private readonly api = inject(ApiService);
  private readonly alerts = inject(AlertController);
  private readonly nav = inject(NavController);
  private readonly notify = inject(NotifyService);
  protected readonly auth = inject(AuthService);
  private readonly i18n = inject(I18nService);

  readonly wishlists = signal<Wishlist[]>([]);
  readonly loading = signal(true);

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

  async create(): Promise<void> {
    const alert = await this.alerts.create({
      header: this.i18n.t('wishlists.new'),
      inputs: [
        { name: 'title', placeholder: this.i18n.t('wishlists.titlePlaceholder'), attributes: { maxlength: 120 } },
        { name: 'eventDate', type: 'date', label: this.i18n.t('wishlists.dateOptional') },
      ],
      buttons: [
        { text: this.i18n.t('common.cancel'), role: 'cancel' },
        { text: this.i18n.t('wishlists.create'), role: 'confirm' },
      ],
    });
    await alert.present();
    const { role, data } = await alert.onDidDismiss<{ values: { title: string; eventDate: string } }>();
    const title = data?.values.title?.trim();
    if (role !== 'confirm' || !title) return;

    try {
      const wishlist = await this.api.createWishlist({
        title,
        description: null,
        eventDate: data?.values.eventDate || null,
      });
      await this.nav.navigateForward(['/s', wishlist.shareToken]);
    } catch (error) {
      await this.notify.error(error);
    }
  }

  async logout(): Promise<void> {
    this.auth.logout();
    await this.nav.navigateRoot('/login');
  }
}
