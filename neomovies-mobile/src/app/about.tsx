import { router } from 'expo-router';
import { useState } from 'react';
import { Alert, Platform, View } from 'react-native';
import Constants from 'expo-constants';
import { Image } from 'expo-image';
import { FileText, RefreshCw, Sparkles } from 'lucide-react-native';
import { FlashList } from '@shopify/flash-list';

import { ListRowItem } from '@/components/list-row-item';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { UpdateSheet } from '@/components/update-sheet';
import { useTheme } from '@/hooks/use-theme';
import { useI18n } from '@/i18n';
import { createAboutScreenStyles } from '@/styles/about-screen.styles';
import { compareVersions, fetchLatestRelease, type GitHubRelease } from '@/lib/github-releases';

export default function AboutScreen() {
  const theme = useTheme();
  const styles = createAboutScreenStyles(theme);
  const { copy } = useI18n();
  const extra = Constants.expoConfig?.extra as
    | { branch?: string; build?: string; releaseType?: string; githubRepo?: string }
    | undefined;
  const appName = Constants.expoConfig?.name || copy.appName;
  const version = Constants.nativeAppVersion || Constants.expoConfig?.version || '—';
  const releaseType = extra?.releaseType || (__DEV__ ? 'dev' : 'release');
  const branch = extra?.branch || releaseType;
  const configBuild =
    Platform.OS === 'ios'
      ? Constants.expoConfig?.ios?.buildNumber
      : Constants.expoConfig?.android?.versionCode != null
        ? String(Constants.expoConfig.android.versionCode)
        : null;
  const baseBuild = Constants.nativeBuildVersion || configBuild || '—';
  const build = extra?.build || baseBuild;
  const appIconUri = Constants.expoConfig?.icon || null;
  const appIconSource = appIconUri && /^https?:\/\//.test(appIconUri)
    ? { uri: appIconUri }
    : require('@/assets/icons/splash-icon.png');

  const [checking, setChecking] = useState(false);
  const [updateRelease, setUpdateRelease] = useState<GitHubRelease | null>(null);
  const [showUpdateSheet, setShowUpdateSheet] = useState(false);

  const handleCheckUpdates = async () => {
    setChecking(true);
    try {
      const repo = extra?.githubRepo || 'Neo-Open-Source/neomovies-mobile';
      const includePrerelease = branch === 'prerelease';
      const latest = await fetchLatestRelease(repo, includePrerelease);

      if (!latest) {
        Alert.alert(copy.about.updateError);
        return;
      }

      const comparison = compareVersions(version, latest.tag_name);
      if (comparison < 0) {
        setUpdateRelease(latest);
        setShowUpdateSheet(true);
      } else {
        Alert.alert(copy.about.updateNoNew);
      }
    } catch {
      Alert.alert(copy.about.updateError);
    } finally {
      setChecking(false);
    }
  };

  return (
    <ThemedView style={styles.container}>
      <FlashList
        data={[{ id: 'about' }]}
        keyExtractor={(item) => item.id}
        showsVerticalScrollIndicator={false}
        renderItem={() => (
          <View style={styles.content}>
        <View style={styles.centeredIconWrap}>
          <Image source={appIconSource} style={styles.centeredAppIcon} contentFit="cover" />
        </View>
        <ThemedText style={styles.appDescription}>{copy.about.appDescription}</ThemedText>

        <View style={styles.listStack}>
          <ListRowItem
            title={copy.about.checkUpdates}
            subtitle={copy.about.checkUpdatesDesc}
            value={checking ? copy.about.updateChecking : undefined}
            onPress={handleCheckUpdates}
            showChevron
            leftAccessory={
              <View style={styles.iconWrapper}>
                <RefreshCw size={18} color={theme.textSecondary} />
              </View>
            }
          />
          <ListRowItem
            title={copy.about.credits}
            subtitle={copy.about.creditsDesc}
            onPress={() => router.push('/credits')}
            showChevron
            leftAccessory={
              <View style={styles.iconWrapper}>
                <Sparkles size={18} color={theme.textSecondary} />
              </View>
            }
          />
          <ListRowItem
            title={copy.about.changelog}
            subtitle={copy.about.changelogDesc}
            onPress={() => router.push('/changelog')}
            showChevron
            leftAccessory={
              <View style={styles.iconWrapper}>
                <FileText size={18} color={theme.textSecondary} />
              </View>
            }
          />
        </View>

        <View style={styles.versionCard}>
          <View style={styles.versionHeader}>
            <ThemedText style={styles.preferenceTitle}>{appName}</ThemedText>
          </View>
          <View style={styles.metaRow}>
            <ThemedText style={styles.metaLabel}>{copy.about.version}</ThemedText>
            <ThemedText style={styles.metaValue}>{version}</ThemedText>
          </View>
          <View style={styles.metaSeparator} />
          <View style={styles.metaRow}>
            <ThemedText style={styles.metaLabel}>{copy.about.branch}</ThemedText>
            <ThemedText style={styles.metaValue}>{branch}</ThemedText>
          </View>
          <View style={styles.metaSeparator} />
          <View style={styles.metaRow}>
            <ThemedText style={styles.metaLabel}>{copy.about.build}</ThemedText>
            <ThemedText style={styles.metaValue}>{build}</ThemedText>
          </View>
        </View>
          </View>
        )}
      />

      <UpdateSheet
        visible={showUpdateSheet}
        release={updateRelease}
        onDismiss={() => setShowUpdateSheet(false)}
        onDownload={() => setShowUpdateSheet(false)}
      />
    </ThemedView>
  );
}
