import * as SecureStore from 'expo-secure-store';
import React, { createContext, ReactNode, useContext, useEffect, useMemo, useState } from 'react';
import { NativeModules, Platform } from 'react-native';

import { dictionaries } from '@/i18n/dictionaries';
import type { Dictionary, Locale } from '@/i18n/types';

const LOCALE_KEY = 'neomovies_locale_v1';
const LOCALE_EXPLICIT_KEY = 'neomovies_locale_explicit_v2';

type I18nContextValue = {
  locale: Locale;
  copy: Dictionary;
  setLocale: (locale: Locale) => void;
};

const I18nContext = createContext<I18nContextValue | null>(null);

function normalizeSystemLocale(raw: string | null | undefined): Locale {
  const value = (raw ?? '').toLowerCase();
  if (value.startsWith('ru')) return 'ru';
  if (value.startsWith('uk')) return 'uk';
  if (value.startsWith('be')) return 'be';
  if (value.startsWith('ro')) return 'ro';
  return 'en';
}

function getSystemLocale(): Locale {
  const getFromNative = () => {
    try {
      if (Platform.OS === 'ios') {
        const preferred =
          (NativeModules.SettingsManager?.settings?.AppleLocale as string | undefined) ??
          (NativeModules.SettingsManager?.settings?.AppleLanguages?.[0] as string | undefined);
        if (preferred) return preferred;
      }
      if (Platform.OS === 'android') {
        const localeIdentifier = NativeModules.I18nManager?.localeIdentifier as string | undefined;
        if (localeIdentifier) return localeIdentifier.replace('_', '-');
      }
    } catch {
      // ignore
    }
    return null;
  };

  try {
    const nativeLocale = getFromNative();
    if (nativeLocale) {
      return normalizeSystemLocale(nativeLocale);
    }
    const intlLocale = Intl.DateTimeFormat().resolvedOptions().locale;
    return normalizeSystemLocale(intlLocale);
  } catch {
    return 'en';
  }
}

export function I18nProvider({ children }: { children: ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>(getSystemLocale());

  useEffect(() => {
    let mounted = true;

    (async () => {
      try {
        const explicit = await SecureStore.getItemAsync(LOCALE_EXPLICIT_KEY);
        if (explicit === '1') {
          const stored = await SecureStore.getItemAsync(LOCALE_KEY);
          if (!mounted) return;
          if (stored && stored in dictionaries) {
            setLocaleState(stored as Locale);
            return;
          }
        }
      } catch {
        // ignore and fallback to system locale
      }

      try {
        const stored = await SecureStore.getItemAsync(LOCALE_KEY);
        if (!mounted) return;
        const initial = getSystemLocale();
        setLocaleState(initial);
        const shouldWrite = !stored || stored !== initial;
        if (shouldWrite) {
          await SecureStore.setItemAsync(LOCALE_KEY, initial);
        }
        return;
      } catch {
        // ignore and fallback to system locale
      }
    })();

    return () => {
      mounted = false;
    };
  }, []);

  const setLocale = (nextLocale: Locale) => {
    setLocaleState(nextLocale);
    void Promise.all([
      SecureStore.setItemAsync(LOCALE_KEY, nextLocale),
      SecureStore.setItemAsync(LOCALE_EXPLICIT_KEY, '1'),
    ]);
  };

  const value = useMemo<I18nContextValue>(
    () => ({
      locale,
      copy: dictionaries[locale],
      setLocale,
    }),
    [locale]
  );

  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

export function useI18n() {
  const context = useContext(I18nContext);
  if (!context) {
    throw new Error('useI18n must be used within I18nProvider');
  }
  return context;
}
