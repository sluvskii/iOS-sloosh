import { View } from 'react-native';
import { FlashList } from '@shopify/flash-list';

import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { useTheme } from '@/hooks/use-theme';
import { useI18n } from '@/i18n';
import { createStaticPageStyles } from '@/styles/static-page.styles';

export default function UpdatesScreen() {
  const styles = createStaticPageStyles(useTheme());
  const { copy } = useI18n();

  return (
    <ThemedView style={styles.container}>
      <FlashList
        data={[{ id: 'updates' }]}
        keyExtractor={(item) => item.id}
        estimatedItemSize={220}
        showsVerticalScrollIndicator={false}
        contentContainerStyle={styles.content}
        renderItem={() => (
          <View style={styles.card}>
            <ThemedText style={styles.text}>
              {copy.profile.updates} (заглушка). История изменений и релиз-ноты.
            </ThemedText>
          </View>
        )}
      />
    </ThemedView>
  );
}
