import { en } from '@/i18n/locales/en';
import { ru } from '@/i18n/locales/ru';
import { uk } from '@/i18n/locales/uk';
import { be } from '@/i18n/locales/be';
import { ro } from '@/i18n/locales/ro';
import type { Dictionary, Locale } from '@/i18n/types';

export type { Locale };

export const dictionaries: Record<Locale, Dictionary> = {
  en,
  ru,
  uk,
  be,
  ro,
};
