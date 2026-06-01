import { View } from 'react-native';
import { Server } from 'lucide-react-native';
import { FlashList } from '@shopify/flash-list';

import { SelectionItem } from '@/components/selection-item';
import { ThemedView } from '@/components/themed-view';
import { useI18n } from '@/i18n';
import { useTheme } from '@/hooks/use-theme';
import { ContentSource, useContentSource } from '@/hooks/use-content-source';
import { createSourceScreenStyles } from '@/styles/source-screen.styles';

export default function SourceSelectionScreen() {
  const theme = useTheme();
  const { copy } = useI18n();
  const styles = createSourceScreenStyles(theme);
  const { source: selectedSource, setSource } = useContentSource();
  const sources: { id: ContentSource; name: string; description: string }[] = [
    {
      id: 'collaps',
      name: copy.settings.sourceDefaultTitle,
      description: copy.settings.sourceDefaultDesc,
    },
    {
      id: 'alloha',
      name: copy.settings.sourceAlternativeTitle,
      description: copy.settings.sourceAlternativeDesc,
    },
  ];

  const handleSelectSource = (id: ContentSource) => {
    void setSource(id);
  };

  return (
    <ThemedView style={styles.container}>
      <FlashList
        data={sources}
        keyExtractor={(item) => item.id}
        estimatedItemSize={88}
        showsVerticalScrollIndicator={false}
        contentContainerStyle={styles.content}
        ItemSeparatorComponent={() => <View style={styles.itemSeparator} />}
        renderItem={({ item: source }) => {
          const isSelected = selectedSource === source.id;
          return (
            <SelectionItem
              title={source.name}
              subtitle={source.description}
              selected={isSelected}
              onPress={() => handleSelectSource(source.id)}
              leftAccessory={
                <View style={styles.iconWrapper}>
                  <Server size={20} color={theme.textSecondary} />
                </View>
              }
            />
          );
        }}
      />
    </ThemedView>
  );
}
