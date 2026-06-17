import { Image } from 'expo-image';
import { ChevronRight, Info, LogIn, LogOut, Settings } from 'lucide-react-native';
import { router } from 'expo-router';
import { Pressable, View } from 'react-native';
import { FlashList } from '@shopify/flash-list';

import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { useProfileScreen } from '@/hooks/use-profile-screen';
import { useTheme } from '@/hooks/use-theme';
import { useI18n } from '@/i18n';
import { createProfileScreenStyles } from '@/styles/profile-screen.styles';

export default function ProfileScreen() {
  const { copy } = useI18n();
  const theme = useTheme();
  const styles = createProfileScreenStyles(theme);
  const {
    loading,
    authenticating,
    error,
    isAuthenticated,
    profile,
    preferredName,
    onLogin,
    onLogout,
  } = useProfileScreen();

  const menuItems = [
    { label: copy.profile.settings, route: '/settings', icon: <Settings size={18} color={theme.textSecondary} /> },
    { label: copy.profile.about, route: '/about', icon: <Info size={18} color={theme.textSecondary} /> },
  ];

  return (
    <ThemedView style={styles.container}>
      <FlashList
        data={[{ id: 'profile' }]}
        keyExtractor={(item) => item.id}
        estimatedItemSize={760}
        showsVerticalScrollIndicator={false}
        renderItem={() => (
          <View style={styles.content}>
        <View style={styles.profileCard}>
          {isAuthenticated && profile?.avatar ? (
            <Image 
              source={{ uri: profile.avatar }} 
              style={styles.avatar} 
              contentFit="cover" 
              transition={0}
              cachePolicy="memory-disk"
              priority="high"
            />
          ) : null}
          <ThemedText style={styles.profileTitle}>
            {isAuthenticated ? preferredName : copy.profile.authTitle}
          </ThemedText>
          <ThemedText style={styles.profileEmail}>
            {isAuthenticated
              ? loading
                ? copy.profile.loadingProfile
                : profile?.email || copy.profile.loadingProfile
              : copy.profile.authDescription}
          </ThemedText>
          {!isAuthenticated ? (
            <Pressable style={styles.loginButton} onPress={() => onLogin()} disabled={authenticating}>
              <View style={styles.loginButtonContent}>
                <LogIn size={16} color="#FFFFFF" />
                <ThemedText style={styles.loginButtonText}>
                  {authenticating ? copy.profile.authLoading : copy.profile.authAction}
                </ThemedText>
              </View>
            </Pressable>
          ) : null}
        </View>

        <View style={styles.menu}>
          {menuItems.map((item, index) => (
            <Pressable
              key={item.label}
              onPress={() => router.push(item.route as never)}
              style={[styles.menuItem, index === menuItems.length - 1 ? styles.menuItemLast : null]}>
              <View style={styles.menuItemLeft}>
                {item.icon}
                <ThemedText style={styles.menuItemLabel}>{item.label}</ThemedText>
              </View>
              <ChevronRight size={18} color={theme.textSecondary} />
            </Pressable>
          ))}
        </View>

        {isAuthenticated ? (
          <Pressable style={styles.logoutButton} onPress={() => onLogout()}>
            <View style={styles.menuItemLeft}>
              <LogOut size={17} color="#FFFFFF" />
              <ThemedText style={styles.logoutText}>{copy.profile.logout}</ThemedText>
            </View>
          </Pressable>
        ) : null}
        {error ? <ThemedText style={styles.errorText}>{error}</ThemedText> : null}
          </View>
        )}
      />
    </ThemedView>
  );
}
