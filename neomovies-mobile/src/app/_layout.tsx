import { ThemeProvider, type Theme } from '@react-navigation/native';
import * as ScreenOrientation from 'expo-screen-orientation';
import { Slot, usePathname } from 'expo-router';
import React from 'react';
import { View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { AnimatedSplashScreen } from '@/components/splash-screen';
import { NavBar } from '@/components/nav-bar';
import { OfflineBanner } from '@/components/offline-banner';
import { ScreenTitle } from '@/components/screen-title';
import { AppTamaguiProvider } from '@/components/tamagui-provider';
import { Colors } from '@/constants/theme';
import { AppThemeProvider, useAppTheme } from '@/hooks/use-app-theme';
import { I18nProvider } from '@/i18n';
import { hydrateOfflineMode } from '@/lib/offline-mode';
import { createRootLayoutStyles } from '@/styles/root-layout.styles';

export default function TabLayout() {
  return (
    <AppThemeProvider>
      <I18nProvider>
        <TabLayoutContent />
      </I18nProvider>
    </AppThemeProvider>
  );
}

function TabLayoutContent() {
  const { resolvedTheme } = useAppTheme();
  const pathname = usePathname();
  const isDetailsScreen = pathname.startsWith('/media/');
  const palette = Colors[resolvedTheme];
  const styles = createRootLayoutStyles(palette.chrome);
  const navigationTheme: Theme = {
    dark: resolvedTheme === 'dark',
    colors: {
      primary: palette.accent,
      background: palette.background,
      card: palette.backgroundElement,
      text: palette.text,
      border: palette.border,
      notification: palette.accent,
    },
    fonts: {
      regular: {
        fontFamily: 'System',
        fontWeight: '400',
      },
      medium: {
        fontFamily: 'System',
        fontWeight: '500',
      },
      bold: {
        fontFamily: 'System',
        fontWeight: '700',
      },
      heavy: {
        fontFamily: 'System',
        fontWeight: '800',
      },
    },
  };

  React.useEffect(() => {
    void hydrateOfflineMode();
  }, []);

  React.useEffect(() => {
    void ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.PORTRAIT_UP);
  }, []);

  return (
    <AppTamaguiProvider>
      <ThemeProvider value={navigationTheme}>
        <AnimatedSplashScreen />
        <SafeAreaView style={styles.safeArea} edges={['top', 'bottom']}>
          <ScreenTitle />
          <OfflineBanner />
          <View style={styles.content}>
            <Slot />
          </View>
          {!isDetailsScreen ? <NavBar /> : null}
        </SafeAreaView>
      </ThemeProvider>
    </AppTamaguiProvider>
  );
}
