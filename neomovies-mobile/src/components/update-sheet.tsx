import { Modal, Pressable, ScrollView, StyleSheet, View } from 'react-native';
import * as Linking from 'expo-linking';

import { ThemedText } from '@/components/themed-text';
import { useTheme } from '@/hooks/use-theme';
import { useI18n } from '@/i18n';
import type { GitHubRelease } from '@/lib/github-releases';
import { formatBytes, parseChangelog } from '@/lib/github-releases';

interface UpdateSheetProps {
  visible: boolean;
  release: GitHubRelease | null;
  onDismiss: () => void;
  onDownload: (url: string) => void;
}

export function UpdateSheet({ visible, release, onDismiss, onDownload }: UpdateSheetProps) {
  const theme = useTheme();
  const { copy } = useI18n();

  if (!release) return null;

  const changelog = parseChangelog(release.body);
  const asset = release.assets[0];
  const downloadUrl = asset?.browser_download_url || '';
  const fileSize = asset ? formatBytes(asset.size) : '';

  const handleDownload = () => {
    if (downloadUrl) {
      onDownload(downloadUrl);
      void Linking.openURL(downloadUrl);
    }
  };

  return (
    <Modal
      visible={visible}
      transparent
      animationType="slide"
      onRequestClose={onDismiss}
    >
      <Pressable style={styles.backdrop} onPress={onDismiss}>
        <Pressable style={[styles.sheet, { backgroundColor: theme.background }]} onPress={(e) => e.stopPropagation()}>
          <View style={styles.handle} />

          <ThemedText style={[styles.title, { color: theme.text }]}>
            {copy.about.updateAvailable}
          </ThemedText>

          <ThemedText style={[styles.version, { color: theme.textSecondary }]}>
            {release.name || release.tag_name} • {fileSize}
          </ThemedText>

          <ScrollView style={styles.changelogScroll} showsVerticalScrollIndicator={false}>
            {changelog.map((change, index) => (
              <View key={index} style={styles.changelogItem}>
                <ThemedText style={[styles.changelogHash, { color: theme.textSecondary }]}>
                  {change.substring(0, 7)}:
                </ThemedText>
                <ThemedText style={[styles.changelogText, { color: theme.text }]}>
                  {change.substring(7).trim() || change}
                </ThemedText>
              </View>
            ))}
          </ScrollView>

          <Pressable
            style={[styles.downloadButton, { backgroundColor: theme.tint }]}
            onPress={handleDownload}
          >
            <ThemedText style={[styles.downloadButtonText, { color: '#fff' }]}>
              {copy.about.updateDownload}
            </ThemedText>
          </Pressable>

          <Pressable style={styles.laterButton} onPress={onDismiss}>
            <ThemedText style={[styles.laterButtonText, { color: theme.textSecondary }]}>
              {copy.about.updateRemindLater}
            </ThemedText>
          </Pressable>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
    justifyContent: 'flex-end',
  },
  sheet: {
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    paddingHorizontal: 20,
    paddingBottom: 40,
    maxHeight: '80%',
  },
  handle: {
    width: 40,
    height: 4,
    backgroundColor: '#ccc',
    borderRadius: 2,
    alignSelf: 'center',
    marginTop: 12,
    marginBottom: 20,
  },
  title: {
    fontSize: 22,
    fontWeight: '600',
    textAlign: 'center',
    marginBottom: 8,
  },
  version: {
    fontSize: 15,
    textAlign: 'center',
    marginBottom: 20,
  },
  changelogScroll: {
    maxHeight: 300,
    marginBottom: 20,
  },
  changelogItem: {
    flexDirection: 'row',
    marginBottom: 8,
    paddingRight: 10,
  },
  changelogHash: {
    fontSize: 13,
    fontFamily: 'monospace',
    marginRight: 6,
    flexShrink: 0,
  },
  changelogText: {
    fontSize: 13,
    flex: 1,
    lineHeight: 18,
  },
  downloadButton: {
    paddingVertical: 16,
    borderRadius: 12,
    alignItems: 'center',
    marginBottom: 12,
  },
  downloadButtonText: {
    fontSize: 16,
    fontWeight: '600',
  },
  laterButton: {
    paddingVertical: 12,
    alignItems: 'center',
  },
  laterButtonText: {
    fontSize: 15,
  },
});
