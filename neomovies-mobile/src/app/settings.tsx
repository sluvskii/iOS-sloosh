import { router } from 'expo-router';
import { useState, useEffect, useCallback } from 'react';
import { Alert, Pressable, View } from 'react-native';
import { Database, Globe, Palette, Server } from 'lucide-react-native';
import { FlashList } from '@shopify/flash-list';
import { Image } from 'expo-image';
import { Directory, File, Paths } from 'expo-file-system';

import { ListRowItem } from '@/components/list-row-item';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { useAppTheme } from '@/hooks/use-app-theme';
import { useContentSource } from '@/hooks/use-content-source';
import { useTheme } from '@/hooks/use-theme';
import { useI18n } from '@/i18n';
import { createSettingsScreenStyles } from '@/styles/settings-screen.styles';
import type { Locale } from '@/i18n/types';

function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`;
}

async function getCacheSize(): Promise<number> {
  try {
    return getDirectorySize(Paths.cache);
  } catch {
    return 0;
  }
}

function getDirectorySize(dir: Directory): number {
  let total = 0;
  try {
    const items = dir.list();
    for (const item of items) {
      if (item instanceof Directory) {
        total += getDirectorySize(item);
      } else if (item instanceof File) {
        total += item.size;
      }
    }
  } catch {
    return 0;
  }
  return total;
}

async function clearAllCache(): Promise<void> {
  try {
    // Clear expo-image cache
    await Image.clearDiskCache();
    await Image.clearMemoryCache();
    
    // Clear file system cache
    const items = Paths.cache.list();
    for (const item of items) {
      try {
        item.delete();
      } catch {
        // Skip undeletable items
      }
    }
  } catch {
    // Ignore errors
  }
}

const LANGUAGES: { code: Locale; name: string }[] = [
  { code: 'en', name: 'English' },
  { code: 'ru', name: 'Русский' },
  { code: 'uk', name: 'Українська' },
  { code: 'be', name: 'Беларуская' },
  { code: 'ro', name: 'Română' },
];

export default function SettingsScreen() {
  const theme = useTheme();
  const { resolvedTheme, toggleTheme } = useAppTheme();
  const styles = createSettingsScreenStyles(theme);
  const { copy, locale } = useI18n();
  const { source } = useContentSource();
  const isDarkTheme = resolvedTheme === 'dark';
  const sourceLabel = source === 'alloha' ? copy.settings.sourceAlternativeTitle : copy.settings.sourceDefaultTitle;
  
  const [cacheSize, setCacheSize] = useState<string>('...');
  const [isClearing, setIsClearing] = useState(false);
  
  const updateCacheSize = useCallback(async () => {
    try {
      const size = await getCacheSize();
      setCacheSize(formatBytes(size));
    } catch {
      setCacheSize('0 B');
    }
  }, []);
  
  useEffect(() => {
    void updateCacheSize();
  }, [updateCacheSize]);
  
  const handleClearCache = async () => {
    setIsClearing(true);
    try {
      await clearAllCache();
      setCacheSize('0 B');
      Alert.alert(copy.settings.clearCache, 'OK');
    } catch {
      Alert.alert('Error', 'Failed to clear cache');
    } finally {
      setIsClearing(false);
    }
  };

  return (
    <ThemedView style={styles.container}>
      <FlashList
        data={[{ id: 'settings' }]}
        keyExtractor={(item) => item.id}
        estimatedItemSize={760}
        showsVerticalScrollIndicator={false}
        renderItem={() => (
          <View style={styles.content}>
        <View style={styles.section}>
          <ThemedText style={styles.sectionTitle}>{copy.settings.common}</ThemedText>

          <ListRowItem
            title={copy.settings.source}
            value={sourceLabel}
            onPress={() => router.push('/settings/source')}
            showChevron
            leftAccessory={
              <View style={styles.iconWrapper}>
                <Server size={20} color={theme.textSecondary} />
              </View>
            }
          />

          <ListRowItem
            title={copy.settings.language}
            value={LANGUAGES.find((l) => l.code === locale)?.name}
            onPress={() => router.push('/settings/language')}
            showChevron
            leftAccessory={
              <View style={styles.iconWrapper}>
                <Globe size={20} color={theme.textSecondary} />
              </View>
            }
          />
        </View>

        <View style={styles.section}>
          <ThemedText style={styles.sectionTitle}>{copy.settings.appearance}</ThemedText>
          
          <View style={styles.settingItem}>
            <View style={styles.settingLeft}>
              <View style={styles.iconWrapper}>
                <Palette size={20} color={theme.textSecondary} />
              </View>
              <ThemedText style={styles.settingLabel}>{copy.settings.darkTheme}</ThemedText>
            </View>
            <Pressable 
              style={[styles.toggle, isDarkTheme && styles.toggleActive]}
              onPress={toggleTheme}>
              <View style={[styles.toggleThumb, isDarkTheme && styles.toggleThumbActive]} />
            </Pressable>
          </View>
        </View>

        <View style={styles.section}>
          <ThemedText style={styles.sectionTitle}>{copy.settings.storage}</ThemedText>
          
          <ListRowItem
            title={copy.settings.clearCache}
            subtitle={copy.settings.clearCacheDesc}
            value={isClearing ? '...' : cacheSize}
            onPress={handleClearCache}
            leftAccessory={
              <View style={styles.iconWrapper}>
                <Database size={20} color={theme.textSecondary} />
              </View>
            }
          />
        </View>
          </View>
        )}
      />
    </ThemedView>
  );
}
