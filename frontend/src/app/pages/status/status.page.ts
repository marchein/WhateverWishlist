import { Component, inject, signal } from '@angular/core';
import {
  IonBackButton, IonButton, IonButtons, IonContent, IonHeader, IonItem, IonLabel,
  IonList, IonSpinner, IonTitle, IonToolbar, type ViewWillEnter,
} from '@ionic/angular';
import { version } from '../../../../package.json';
import { API_URL, ApiService } from '../../core/api.service';
import { TranslatePipe } from '../../core/i18n/i18n';
import { NotifyService } from '../../core/ui';

@Component({
  selector: 'app-status',
  templateUrl: 'status.page.html',
  imports: [
    TranslatePipe, IonBackButton, IonButton, IonButtons, IonContent, IonHeader,
    IonItem, IonLabel, IonList, IonSpinner, IonTitle, IonToolbar,
  ],
})
export class StatusPage implements ViewWillEnter {
  private readonly api = inject(ApiService);
  private readonly notify = inject(NotifyService);
  readonly frontendVersion = version;
  readonly backendAddress = new URL(API_URL, window.location.origin).href;
  readonly backendVersion = signal<string | null>(null);
  readonly loading = signal(true);
  readonly failed = signal(false);

  ionViewWillEnter(): void {
    void this.load();
  }

  async load(): Promise<void> {
    this.loading.set(true);
    this.failed.set(false);
    this.backendVersion.set(null);
    try {
      const health = await this.api.health();
      if (health.ok !== true) throw new Error('Backend health check failed');
      this.backendVersion.set(health.version ?? null);
    } catch (error) {
      this.failed.set(true);
      await this.notify.error(error);
    } finally {
      this.loading.set(false);
    }
  }
}
