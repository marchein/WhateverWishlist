import { Component, inject } from '@angular/core';
import { IonApp, IonRouterOutlet } from '@ionic/angular';
import { registerAppIcons } from './core/icons';
import { I18nService } from './core/i18n/i18n';

@Component({
  selector: 'app-root',
  templateUrl: 'app.component.html',
  imports: [IonApp, IonRouterOutlet],
})
export class AppComponent {
  constructor() {
    // Instantiated eagerly so <html lang> and the document title follow the language from the start.
    inject(I18nService);
    registerAppIcons();
  }
}
