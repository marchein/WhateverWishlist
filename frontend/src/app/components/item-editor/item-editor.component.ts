import { Component, Input, OnInit, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import {
  AlertController,
  IonButton,
  IonButtons,
  IonCard,
  IonCardContent,
  IonCardHeader,
  IonCardSubtitle,
  IonContent,
  IonHeader,
  IonIcon,
  IonInput,
  IonItem,
  IonLabel,
  IonList,
  IonListHeader,
  IonNote,
  IonSpinner,
  IonTextarea,
  IonTitle,
  IonToolbar,
  ModalController,
} from '@ionic/angular';
import { ApiService } from '../../core/api.service';
import { I18nService, isTranslationKey, PricePipe, TranslatePipe, type TranslationKey } from '../../core/i18n/i18n';
import type { Item, ItemInput, ScrapeMessage, ScrapeResult, ScrapeSource } from '../../core/models';
import { AssetUrlPipe, HostnamePipe, NotifyService } from '../../core/ui';
import { PriorityStarsComponent } from '../priority-stars.component';

const STATUS: Record<ScrapeResult['status'], { icon: string; color: string; text: TranslationKey }> = {
  ok: { icon: 'checkmark-circle', color: 'success', text: 'scrape.status.ok' },
  partial: { icon: 'warning-outline', color: 'warning', text: 'scrape.status.partial' },
  failed: { icon: 'alert-circle', color: 'danger', text: 'scrape.status.failed' },
};

/** Modal for creating/editing a wish. Pasting a link fills in what the backend could figure out. */
@Component({
  selector: 'app-item-editor',
  templateUrl: 'item-editor.component.html',
  styleUrls: ['item-editor.component.scss'],
  imports: [
    ReactiveFormsModule,
    TranslatePipe,
    AssetUrlPipe,
    HostnamePipe,
    PricePipe,
    PriorityStarsComponent,
    IonHeader,
    IonToolbar,
    IonTitle,
    IonButtons,
    IonButton,
    IonContent,
    IonInput,
    IonTextarea,
    IonIcon,
    IonSpinner,
    IonNote,
    IonCard,
    IonCardHeader,
    IonCardSubtitle,
    IonCardContent,
    IonList,
    IonListHeader,
    IonItem,
    IonLabel,
  ],
})
export class ItemEditorComponent implements OnInit {
  // Plain @Inputs because Ionic assigns modal componentProps as properties.
  @Input({ required: true }) wishlistId!: string;
  @Input() item?: Item;

  private readonly api = inject(ApiService);
  private readonly modalCtrl = inject(ModalController);
  private readonly alerts = inject(AlertController);
  private readonly notify = inject(NotifyService);
  private readonly i18n = inject(I18nService);

  readonly form = new FormGroup({
    title: new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.maxLength(300)] }),
    imageUrl: new FormControl('', { nonNullable: true }),
    price: new FormControl<number | null>(null, { validators: [Validators.min(0)] }),
    currency: new FormControl('EUR', { nonNullable: true, validators: [Validators.pattern(/^[A-Za-z]{3}$/)] }),
    priority: new FormControl(3, { nonNullable: true }),
    quantity: new FormControl(1, { nonNullable: true, validators: [Validators.required, Validators.min(1), Validators.max(999)] }),
    notes: new FormControl('', { nonNullable: true, validators: [Validators.maxLength(2000)] }),
  });

  readonly links = signal<string[]>([]);
  readonly newLink = signal('');
  readonly pasted = signal('');
  readonly result = signal<ScrapeResult | null>(null);
  readonly scraping = signal(false);
  readonly uploading = signal(false);
  readonly saving = signal(false);
  readonly imageFailed = signal(false);
  protected readonly status = STATUS;

  constructor() {
    this.form.controls.imageUrl.valueChanges.pipe(takeUntilDestroyed()).subscribe(() => this.imageFailed.set(false));
  }

  /** An unchanged saved URL previews the cached copy; a new URL is shown as typed. */
  get previewImageUrl(): string | null {
    const url = this.form.controls.imageUrl.value;
    if (!url) return null;
    if (this.item?.imageUrl === url && this.item.displayImageUrl) return this.item.displayImageUrl;
    return url;
  }

  ngOnInit(): void {
    if (!this.item) return;
    this.form.patchValue({
      title: this.item.title,
      imageUrl: this.item.imageUrl ?? '',
      price: this.item.price,
      currency: this.item.currency ?? 'EUR',
      priority: this.item.priority,
      quantity: this.item.quantity,
      notes: this.item.notes ?? '',
    });
    this.links.set([...this.item.links]);
  }

  onPaste(event: ClipboardEvent): void {
    const text = event.clipboardData?.getData('text') ?? '';
    if (!text.trim()) return;
    event.preventDefault();
    this.pasted.set(text);
    void this.fetchDetails();
  }

  async fetchDetails(): Promise<void> {
    const input = this.pasted().trim();
    if (!input || this.scraping()) return;
    this.scraping.set(true);
    try {
      const result = await this.api.scrape(input);
      this.fillEmptyFields(result);
      this.result.set(result);
      this.pasted.set('');
    } catch (error) {
      await this.notify.error(error);
    } finally {
      this.scraping.set(false);
    }
  }

  /** Never overwrites what the user already entered; the result card offers "Use" buttons for that. */
  private fillEmptyFields(result: ScrapeResult): void {
    const { title, imageUrl, price, currency } = this.form.controls;
    if (result.title && !title.value.trim()) title.setValue(result.title);
    if (result.image && !imageUrl.value) imageUrl.setValue(result.image);
    if (result.price !== null && price.value === null) {
      price.setValue(result.price);
      if (result.currency) currency.setValue(result.currency);
    }
    const link = result.url;
    if (link && !this.links().includes(link)) this.links.update((links) => [...links, link]);
  }

  use(field: 'title' | 'image' | 'price'): void {
    const result = this.result();
    if (!result) return;
    const { title, imageUrl, price, currency } = this.form.controls;
    if (field === 'title' && result.title) title.setValue(result.title);
    if (field === 'image' && result.image) imageUrl.setValue(result.image);
    if (field === 'price' && result.price !== null) {
      price.setValue(result.price);
      if (result.currency) currency.setValue(result.currency);
    }
  }

  /** Titles taken from the URL slug or the pasted text are only a best guess. */
  isGuess(source: ScrapeSource | undefined): boolean {
    return source === 'link-address' || source === 'pasted-text';
  }

  sourceText(source: ScrapeSource | undefined): string {
    const key = `scrape.source.${source}`;
    return isTranslationKey(key) ? this.i18n.t(key) : '';
  }

  messageText(message: ScrapeMessage): string {
    const key = `scrape.msg.${message.code}`;
    return isTranslationKey(key) ? this.i18n.t(key, message.params) : message.message;
  }

  async onFileSelected(event: Event): Promise<void> {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = '';
    if (!file) return;
    if (file.size > 5 * 1024 * 1024) {
      await this.notify.error(this.i18n.t('editor.imageTooLarge'));
      return;
    }
    this.uploading.set(true);
    try {
      const { url } = await this.api.uploadImage(file);
      this.form.controls.imageUrl.setValue(url);
    } catch (error) {
      await this.notify.error(error);
    } finally {
      this.uploading.set(false);
    }
  }

  removeImage(): void {
    this.form.controls.imageUrl.setValue('');
  }

  addLink(): void {
    const value = this.newLink().trim();
    if (!value) return;
    const candidate = /^https?:\/\//i.test(value) ? value : `https://${value}`;
    try {
      new URL(candidate);
    } catch {
      void this.notify.error(this.i18n.t('editor.invalidLink'));
      return;
    }
    if (!this.links().includes(candidate)) this.links.update((links) => [...links, candidate]);
    this.newLink.set('');
  }

  removeLink(index: number): void {
    this.links.update((links) => links.filter((_, i) => i !== index));
  }

  async save(): Promise<void> {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      await this.notify.error(
        this.i18n.t(this.form.controls.title.invalid ? 'editor.titleRequired' : 'editor.checkFields'),
      );
      return;
    }
    const value = this.form.getRawValue();
    const input: ItemInput = {
      title: value.title.trim(),
      notes: value.notes.trim() || null,
      imageUrl: value.imageUrl.trim() || null,
      price: value.price ?? null,
      currency: value.currency.trim().toUpperCase() || null,
      priority: value.priority,
      quantity: value.quantity,
      links: this.links(),
    };

    this.saving.set(true);
    try {
      const saved = this.item
        ? await this.api.updateItem(this.wishlistId, this.item.id, input)
        : await this.api.createItem(this.wishlistId, input);
      await this.modalCtrl.dismiss(saved, 'saved');
    } catch (error) {
      await this.notify.error(error);
    } finally {
      this.saving.set(false);
    }
  }

  async delete(): Promise<void> {
    if (!this.item) return;
    const alert = await this.alerts.create({
      header: this.i18n.t('editor.delete.header'),
      message: this.i18n.t('editor.delete.message'),
      buttons: [
        { text: this.i18n.t('common.cancel'), role: 'cancel' },
        { text: this.i18n.t('common.delete'), role: 'destructive' },
      ],
    });
    await alert.present();
    if ((await alert.onDidDismiss()).role !== 'destructive') return;
    try {
      await this.api.deleteItem(this.wishlistId, this.item.id);
      await this.modalCtrl.dismiss(this.item, 'deleted');
    } catch (error) {
      await this.notify.error(error);
    }
  }

  cancel(): void {
    void this.modalCtrl.dismiss(null, 'cancel');
  }
}
