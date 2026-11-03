import { Injectable, Pipe, inject, type PipeTransform } from '@angular/core';
import { ToastController } from '@ionic/angular';
import { environment } from '../../environments/environment';
import { I18nService } from './i18n/i18n';

@Injectable({ providedIn: 'root' })
export class NotifyService {
  private readonly toasts = inject(ToastController);
  private readonly i18n = inject(I18nService);

  async success(message: string): Promise<void> {
    const toast = await this.toasts.create({ message, duration: 2500, color: 'success', position: 'bottom' });
    await toast.present();
  }

  /** Accepts an already translated message or an error (API error codes are translated). */
  async error(error: unknown): Promise<void> {
    const message = typeof error === 'string' ? error : this.i18n.errorMessage(error);
    const toast = await this.toasts.create({ message, duration: 4000, color: 'danger', position: 'bottom' });
    await toast.present();
  }
}

/** Uploaded images and cached images are stored as "/uploads/…" and "/_cache/…" and live on the API server. */
@Pipe({ name: 'assetUrl' })
export class AssetUrlPipe implements PipeTransform {
  transform(url: string | null | undefined): string | null {
    if (!url) return null;
    return (url.startsWith('/uploads/') || url.startsWith('/_cache/')) ? `${environment.apiBaseUrl}${url}` : url;
  }
}

@Pipe({ name: 'hostname' })
export class HostnamePipe implements PipeTransform {
  transform(url: string): string {
    try {
      return new URL(url).hostname.replace(/^www\./, '');
    } catch {
      return url;
    }
  }
}
