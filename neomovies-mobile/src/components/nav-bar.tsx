import { Link, usePathname } from 'expo-router';
import { Image } from 'expo-image';
import { useEffect, useState } from 'react';
import { Pressable, View } from 'react-native';
import { Heart, House, Search, UserRound } from 'lucide-react-native';
import { getProfile } from '@/lib/neoid-auth';
import {
  getCachedProfileState,
  hydrateProfileCache,
  subscribeProfileState,
} from '@/hooks/use-profile-screen';
import { useTheme } from '@/hooks/use-theme';
import { useI18n } from '@/i18n';
import { createNavBarThemeStyles, navBarStyles } from '@/styles/nav-bar.styles';
import { NeoIdUserProfile } from '@/types/neo-id';

type TabItem = {
  name: string;
  href: '/' | '/explore' | '/favorites' | '/profile';
  label: string;
  icon: 'home' | 'search' | 'favorites' | 'profile';
};

function TabIcon({
  icon,
  isActive,
  color,
}: {
  icon: TabItem['icon'];
  isActive: boolean;
  color: string;
}) {
  const size = 26;
  const strokeWidth = isActive ? 2.5 : 2;

  if (icon === 'home') return <House size={size} strokeWidth={strokeWidth} color={color} />;
  if (icon === 'favorites') return <Heart size={size} strokeWidth={strokeWidth} color={color} />;
  if (icon === 'profile') return <UserRound size={size} strokeWidth={strokeWidth} color={color} />;
  return <Search size={size} strokeWidth={strokeWidth} color={color} />;
}

export function NavBar() {
  const pathname = usePathname();
  const theme = useTheme();
  const { copy } = useI18n();
  const themeStyles = createNavBarThemeStyles(theme);
  const cachedState = getCachedProfileState();
  const [isAuthenticated, setIsAuthenticated] = useState(cachedState.isAuthenticated);
  const [profile, setProfile] = useState<NeoIdUserProfile | null>(cachedState.profile);

  useEffect(() => {
    void hydrateProfileCache();
    const unsubscribe = subscribeProfileState((nextProfile, nextIsAuthenticated) => {
      setProfile(nextProfile);
      setIsAuthenticated(nextIsAuthenticated);
    });
    return unsubscribe;
  }, []);

  useEffect(() => {
    if (!isAuthenticated) return;
    let cancelled = false;
    void (async () => {
      try {
        const freshProfile = await getProfile();
        if (cancelled) return;
        setProfile(freshProfile);
      } catch {}
    })();
    return () => {
      cancelled = true;
    };
  }, [isAuthenticated, profile?.avatar]);

  const tabs: TabItem[] = [
    { name: 'index', href: '/', label: copy.tabs.home, icon: 'home' },
    { name: 'explore', href: '/explore', label: copy.tabs.search, icon: 'search' },
    { name: 'favorites', href: '/favorites', label: copy.tabs.favorites, icon: 'favorites' },
    { name: 'profile', href: '/profile', label: copy.tabs.profile, icon: 'profile' },
  ];

  return (
    <View style={[navBarStyles.container, navBarStyles.transparentBackground, themeStyles.container]}>
      <View style={[navBarStyles.tabBar, themeStyles.tabBar]}>
        {tabs.map((tab) => {
          const isActive = pathname === tab.href;
          const iconColor = isActive ? theme.text : theme.textMuted;

          return (
            <Link key={tab.name} href={tab.href as any} asChild>
              <Pressable
                style={({ pressed }) => [
                  navBarStyles.tabItem,
                  isActive ? navBarStyles.tabItemActive : null,
                  pressed ? navBarStyles.tabItemPressed : null,
                ]}>
                <View style={navBarStyles.iconWrapper}>
                  {tab.icon === 'profile' && isAuthenticated && profile?.avatar ? (
                    <Image
                      source={{ uri: profile.avatar }}
                      style={navBarStyles.avatar}
                      contentFit="cover"
                      transition={0}
                      cachePolicy="memory-disk"
                    />
                  ) : (
                    <TabIcon icon={tab.icon} isActive={isActive} color={iconColor} />
                  )}
                </View>
              </Pressable>
            </Link>
          );
        })}
      </View>
    </View>
  );
}