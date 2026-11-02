import { Component, inject, input, signal } from '@angular/core';
import { FormControl, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { RouterLink } from '@angular/router';
import {
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonInput,
  IonLabel,
  IonList,
  IonRouterLink,
  IonSegment,
  IonSegmentButton,
  IonSpinner,
  IonTitle,
  IonToolbar,
  NavController,
} from '@ionic/angular';
import { LanguageSwitchComponent } from '../../components/language-switch.component';
import { AuthService } from '../../core/auth.service';
import { I18nService, TranslatePipe } from '../../core/i18n/i18n';
import { NotifyService } from '../../core/ui';

@Component({
  selector: 'app-login',
  templateUrl: 'login.page.html',
  styleUrls: ['login.page.scss'],
  imports: [
    ReactiveFormsModule,
    RouterLink,
    IonRouterLink,
    TranslatePipe,
    LanguageSwitchComponent,
    IonHeader,
    IonToolbar,
    IonTitle,
    IonContent,
    IonSegment,
    IonSegmentButton,
    IonLabel,
    IonList,
    IonInput,
    IonButton,
    IonButtons,
    IonIcon,
    IonSpinner,
  ],
})
export class LoginPage {
  private readonly auth = inject(AuthService);
  private readonly nav = inject(NavController);
  private readonly notify = inject(NotifyService);
  private readonly i18n = inject(I18nService);

  readonly returnUrl = input<string>();
  readonly mode = signal<'login' | 'register'>('login');
  readonly busy = signal(false);
  readonly showPassword = signal(false);

  readonly form = new FormGroup({
    displayName: new FormControl('', { nonNullable: true }),
    email: new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.email] }),
    password: new FormControl('', { nonNullable: true, validators: [Validators.required, Validators.minLength(8)] }),
  });

  setMode(value: unknown): void {
    this.mode.set(value === 'register' ? 'register' : 'login');
  }

  async submit(): Promise<void> {
    const { displayName, email, password } = this.form.getRawValue();
    if (this.form.invalid || (this.mode() === 'register' && !displayName.trim())) {
      this.form.markAllAsTouched();
      await this.notify.error(
        this.i18n.t(this.mode() === 'register' ? 'login.invalidRegister' : 'login.invalidLogin'),
      );
      return;
    }

    this.busy.set(true);
    try {
      if (this.mode() === 'register') await this.auth.register(email, password, displayName.trim());
      else await this.auth.login(email, password);
      // Only allow in-app redirects.
      const returnUrl = this.returnUrl();
      const target = returnUrl?.startsWith('/') && !returnUrl.startsWith('//') ? returnUrl : '/wishlists';
      await this.nav.navigateRoot(target);
    } catch (error) {
      await this.notify.error(error);
    } finally {
      this.busy.set(false);
    }
  }
}
