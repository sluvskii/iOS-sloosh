import { useEffect, useState } from 'react';
import { View } from 'react-native';
import { WifiOff, Wrench } from 'lucide-react-native';
import { usePathname } from 'expo-router';

import { ThemedText } from '@/components/themed-text';
import { useTheme } from '@/hooks/use-theme';
import { useI18n } from '@/i18n';
import { getOfflineModeSnapshot, subscribeOfflineMode } from '@/lib/offline-mode';
import { getRouteHasCache, subscribeRouteCache } from '@/lib/screen-cache-state';
import { offlineBannerStyles } from '@/styles/offline-banner.styles';

export function OfflineBanner() {
  const pathname = usePathname();
  const theme = useTheme();
  const { copy } = useI18n();
  const [offline, setOffline] = useState(getOfflineModeSnapshot());
  const [, forceUpdate] = useState(0);

  useEffect(() => subscribeOfflineMode(setOffline), []);
  useEffect(() => subscribeRouteCache(() => forceUpdate((v) => v + 1)), []);

  if (!offline.enabled) return null;
  const routeKey =
    pathname === '/'
      ? 'home'
      : pathname === '/explore'
        ? 'explore'
        : pathname === '/favorites'
          ? 'favorites'
          : pathname.startsWith('/category/')
            ? 'category'
            : pathname.startsWith('/media/')
              ? 'media'
              : null;
  if (routeKey && !getRouteHasCache(routeKey)) return null;
  const isNetwork = offline.reason === 'network';
  const text = isNetwork ? copy.appStatus.noInternetDescription : copy.appStatus.maintenanceDescription;

  return (
    <View
      style={[
        offlineBannerStyles.container,
        {
          backgroundColor: theme.backgroundElement,
          borderColor: theme.border,
        },
      ]}>
      <View style={offlineBannerStyles.row}>
        {isNetwork ? (
          <WifiOff size={17} color={theme.accent} strokeWidth={2.2} />
        ) : (
          <Wrench size={17} color={theme.accent} strokeWidth={2.2} />
        )}
        <View style={offlineBannerStyles.copy}>
          <ThemedText type="small" style={offlineBannerStyles.title}>
            {isNetwork ? copy.appStatus.noInternetTitle : copy.appStatus.maintenanceTitle}
          </ThemedText>
          <ThemedText type="small" themeColor="textSecondary">
            {text}
          </ThemedText>
        </View>
      </View>
    </View>
  );
}
