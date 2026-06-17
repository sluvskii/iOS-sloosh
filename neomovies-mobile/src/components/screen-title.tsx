import { router, useGlobalSearchParams, usePathname } from 'expo-router';
import { ChevronLeft, Heart } from 'lucide-react-native';
import { Pressable, View } from 'react-native';
import { useEffect, useState } from 'react';

import { ThemedText } from '@/components/themed-text';
import { useTheme } from '@/hooks/use-theme';
import { useI18n } from '@/i18n';
import { getMediaFavoriteHeader, subscribeMediaFavoriteHeader } from '@/lib/media-favorite-header';
import { screenTitleStyles } from '@/styles/screen-title.styles';

export function ScreenTitle() {
  const pathname = usePathname();
  const params = useGlobalSearchParams<{ title?: string }>();
  const theme = useTheme();
  const { copy } = useI18n();
  const detailsTitle = typeof params.title === 'string' ? decodeURIComponent(params.title) : '';
  const isDetailsScreen = pathname.startsWith('/media/');
  const isCategoryScreen = pathname.startsWith('/category/');
  const isWatchSelectorScreen = pathname.startsWith('/watch/');
  const [favoriteHeader, setFavoriteHeader] = useState(getMediaFavoriteHeader());

  useEffect(() => {
    return subscribeMediaFavoriteHeader((next) => {
      setFavoriteHeader(next);
    });
  }, []);

  const title = isDetailsScreen
    ? detailsTitle || copy.tabs.details
    : isWatchSelectorScreen
      ? detailsTitle || copy.watchSelector.title
    : isCategoryScreen
      ? detailsTitle || copy.home.popular
      : pathname === '/profile'
        ? copy.tabs.profile
      : pathname === '/settings'
        ? copy.profile.settings
      : pathname === '/settings/language'
        ? copy.settings.language
      : pathname === '/settings/source'
        ? copy.settings.source
      : pathname === '/about'
        ? copy.profile.about
      : pathname === '/credits'
        ? copy.about.credits
      : pathname === '/explore'
        ? copy.tabs.search
      : pathname === '/favorites'
        ? copy.tabs.favorites
        : copy.tabs.home;

  const showBackButton =
    isDetailsScreen ||
    isWatchSelectorScreen ||
    isCategoryScreen ||
    pathname === '/settings' ||
    pathname === '/about' ||
    pathname === '/credits' ||
    pathname === '/settings/language' ||
    pathname === '/settings/source';

  return (
    <View style={screenTitleStyles.container}>
      {showBackButton ? (
        <View style={screenTitleStyles.backButton}>
          <Pressable
            onPress={() => {
              if (router.canGoBack()) {
                router.back();
              } else {
                const fallbackRoute =
                  pathname === '/settings' ||
                  pathname === '/about' ||
                  pathname === '/credits' ||
                  pathname === '/settings/language' ||
                  pathname === '/settings/source'
                    ? '/profile'
                    : '/';
                router.replace(fallbackRoute);
              }
            }}
            style={screenTitleStyles.backButtonHit}>
            <ChevronLeft size={24} color={theme.text} strokeWidth={2.4} />
          </Pressable>
        </View>
      ) : null}
      {isDetailsScreen && favoriteHeader.visible ? (
        <View style={screenTitleStyles.rightButton}>
          <Pressable
            style={screenTitleStyles.rightButtonHit}
            onPress={() => favoriteHeader.onPress?.()}
            disabled={favoriteHeader.busy}>
            <Heart
              size={21}
              strokeWidth={2.3}
              color={favoriteHeader.isFavorite ? theme.accent : theme.text}
              fill={favoriteHeader.isFavorite ? theme.accent : 'transparent'}
            />
          </Pressable>
        </View>
      ) : null}
      <ThemedText style={screenTitleStyles.title}>{title}</ThemedText>
    </View>
  );
}
