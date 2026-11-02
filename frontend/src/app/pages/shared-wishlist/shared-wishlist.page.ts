import { Component, computed, inject, input, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import {
  AlertController,
  IonAccordion,
  IonAccordionGroup,
  IonBadge,
  IonButton,
  IonButtons,
  IonCard,
  IonCardContent,
  IonCardHeader,
  IonCardSubtitle,
  IonCardTitle,
  IonChip,
  IonContent,
  IonHeader,
  IonIcon,
  IonItem,
  IonLabel,
  IonRefresher,
  IonRefresherContent,
  IonRouterLink,
  IonSegment,
  IonSegmentButton,
  IonSelect,
  IonSelectOption,
  IonSpinner,
  IonTitle,
  IonToolbar,
  type RefresherCustomEvent,
  type ViewWillEnter,
} from '@ionic/angular';
import { LanguageSwitchComponent } from '../../components/language-switch.component';
import { PriorityStarsComponent } from '../../components/priority-stars.component';
import { ApiService } from '../../core/api.service';
import { AuthService } from '../../core/auth.service';
import { I18nService, LocalDatePipe, PricePipe, TranslatePipe } from '../../core/i18n/i18n';
import type { Purchase, SharedItem, SharedWishlist } from '../../core/models';
import { AssetUrlPipe, HostnamePipe, NotifyService } from '../../core/ui';
import { isFullyBought, SORT_OPTIONS, sortItems, type Sort } from './sort-items';
import { WishlistDetailPage } from '../wishlist-detail/wishlist-detail.page';

type Filter = 'all' | 'open' | 'bought';

/** What friends & family see through the share link. */
@Component({
  selector: 'app-shared-wishlist',
  templateUrl: 'shared-wishlist.page.html',
  styleUrls: ['shared-wishlist.page.scss'],
  imports: [
    WishlistDetailPage,
    LocalDatePipe,
    TranslatePipe,
    RouterLink,
    IonRouterLink,
    AssetUrlPipe,
    HostnamePipe,
    PricePipe,
    PriorityStarsComponent,
    LanguageSwitchComponent,
    IonHeader,
    IonToolbar,
    IonTitle,
    IonButtons,
    IonButton,
    IonIcon,
    IonContent,
    IonRefresher,
    IonRefresherContent,
    IonSegment,
    IonSegmentButton,
    IonSelect,
    IonSelectOption,
    IonLabel,
    IonCard,
    IonCardHeader,
    IonCardTitle,
    IonCardSubtitle,
    IonCardContent,
    IonChip,
    IonBadge,
    IonAccordionGroup,
    IonAccordion,
    IonItem,
    IonSpinner,
  ],
})
export class SharedWishlistPage implements ViewWillEnter {
  private readonly api = inject(ApiService);
  private readonly alerts = inject(AlertController);
  private readonly notify = inject(NotifyService);
  protected readonly auth = inject(AuthService);
  private readonly i18n = inject(I18nService);

  /** Bound from the :token route parameter. */
  readonly token = input.required<string>();
  readonly data = signal<SharedWishlist | null>(null);
  readonly notFound = signal(false);
  readonly revision = signal(0);
  readonly filter = signal<Filter>('all');
  readonly sort = signal<Sort>('newest');
  readonly busyItem = signal<string | null>(null);
  protected readonly sortOptions = SORT_OPTIONS;

  readonly visibleItems = computed(() => {
    const data = this.data();
    if (!data) return [];
    const filter = this.filter();
    const items =
      data.isOwner || filter === 'all'
        ? data.items
        : data.items.filter((item) => (filter === 'bought') === isFullyBought(item));
    return sortItems(items, this.sort(), this.i18n.locale(), !data.isOwner);
  });

  ionViewWillEnter(): void {
    void this.load();
  }

  async load(event?: RefresherCustomEvent): Promise<void> {
    try {
      this.data.set(await this.api.getShared(this.token()));
      this.notFound.set(false);
      this.revision.update((value) => value + 1);
    } catch (error) {
      this.data.set(null);
      this.notFound.set(true);
      await this.notify.error(error);
    } finally {
      await event?.target.complete();
    }
  }

  setFilter(value: unknown): void {
    this.filter.set(value === 'open' || value === 'bought' ? value : 'all');
  }

  setSort(value: unknown): void {
    this.sort.set(SORT_OPTIONS.find((option) => option.value === value)?.value ?? 'newest');
  }

  remaining(item: SharedItem): number {
    return Math.max(0, item.quantity - (item.purchasedQuantity ?? 0));
  }

  isBought(item: SharedItem): boolean {
    return isFullyBought(item);
  }

  /** Someone undid a purchase they didn't make themselves – worth a second look. */
  isSuspicious(purchase: Purchase): boolean {
    return !!purchase.revertedByName && purchase.revertedByName.toLowerCase() !== purchase.buyerName.toLowerCase();
  }

  async markBought(item: SharedItem): Promise<void> {
    const remaining = this.remaining(item);
    const t = this.i18n.t.bind(this.i18n);
    const alert = await this.alerts.create({
      header: t('shared.buy.header'),
      subHeader: item.title,
      message: t('shared.buy.message'),
      inputs: [
        { name: 'name', placeholder: t('common.yourName'), value: this.auth.buyerName, attributes: { maxlength: 60 } },
        ...(remaining > 1
          ? [
              {
                name: 'quantity',
                type: 'number' as const,
                value: 1,
                min: 1,
                max: remaining,
                label: t('shared.buy.quantity', { count: remaining }),
              },
            ]
          : []),
      ],
      buttons: [
        { text: t('common.cancel'), role: 'cancel' },
        { text: t('shared.buy.confirm'), role: 'confirm' },
      ],
    });
    await alert.present();
    const { role, data } = await alert.onDidDismiss<{ values: { name: string; quantity?: string } }>();
    if (role !== 'confirm') return;

    const name = data?.values.name?.trim() ?? '';
    if (!name) {
      await this.notify.error(t('shared.buy.nameRequired'));
      return;
    }
    const quantity = Math.min(remaining, Math.max(1, Number(data?.values.quantity ?? 1) || 1));

    this.busyItem.set(item.id);
    try {
      const updated = await this.api.markPurchased(this.token(), item.id, { name, quantity });
      this.auth.rememberBuyerName(name);
      this.replaceItem(updated);
      await this.notify.success(t('shared.buy.thanks'));
    } catch (error) {
      await this.notify.error(error);
      await this.load();
    } finally {
      this.busyItem.set(null);
    }
  }

  async undo(item: SharedItem, purchase: Purchase): Promise<void> {
    const t = this.i18n.t.bind(this.i18n);
    const alert = await this.alerts.create({
      header: t('shared.undo.header'),
      message: t('shared.undo.message', { name: purchase.buyerName, count: purchase.quantity }),
      inputs: [{ name: 'name', placeholder: t('common.yourName'), value: this.auth.buyerName, attributes: { maxlength: 60 } }],
      buttons: [
        { text: t('common.cancel'), role: 'cancel' },
        { text: t('shared.undo'), role: 'destructive' },
      ],
    });
    await alert.present();
    const { role, data } = await alert.onDidDismiss<{ values: { name: string } }>();
    if (role !== 'destructive') return;
    const name = data?.values.name?.trim() ?? '';
    if (!name) {
      await this.notify.error(t('shared.undo.nameRequired'));
      return;
    }

    this.busyItem.set(item.id);
    try {
      this.auth.rememberBuyerName(name);
      this.replaceItem(await this.api.revertPurchase(this.token(), purchase.id, { name }));
    } catch (error) {
      await this.notify.error(error);
      await this.load();
    } finally {
      this.busyItem.set(null);
    }
  }

  private replaceItem(updated: SharedItem): void {
    this.data.update((data) =>
      data && { ...data, items: data.items.map((item) => (item.id === updated.id ? updated : item)) },
    );
  }
}
