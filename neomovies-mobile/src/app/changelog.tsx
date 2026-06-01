import { View, ScrollView } from 'react-native';
import { History } from 'lucide-react-native';

import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { useTheme } from '@/hooks/use-theme';
import { useI18n } from '@/i18n';
import { createCreditsScreenStyles } from '@/styles/credits-screen.styles';

export default function ChangelogScreen() {
  const theme = useTheme();
  const styles = createCreditsScreenStyles(theme);
  const { copy } = useI18n();

  return (
    <ThemedView style={styles.container}>
      <ScrollView showsVerticalScrollIndicator={false}>
        <View style={styles.content}>
          {copy.changelog.versions.map((entry) => (
            <View key={entry.version} style={styles.section}>
              <View style={styles.sectionHeader}>
                <History size={20} color={theme.accent} />
                <ThemedText style={styles.sectionTitle}>{entry.version}</ThemedText>
              </View>
              
              <View style={styles.creditsCard}>
                {entry.changes.map((change, index, arr) => (
                  <View 
                    key={`${entry.version}-${index}`} 
                    style={[styles.creditItem, index === arr.length - 1 && styles.creditItemLast]}
                  >
                    <ThemedText style={styles.creditDescription}>• {change}</ThemedText>
                  </View>
                ))}
              </View>
            </View>
          ))}
        </View>
      </ScrollView>
    </ThemedView>
  );
}
