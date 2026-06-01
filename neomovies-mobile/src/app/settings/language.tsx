import { View } from 'react-native';
import { Image } from 'expo-image';
import { FlashList } from '@shopify/flash-list';

import { useI18n } from '@/i18n';
import { SelectionItem } from '@/components/selection-item';
import { ThemedView } from '@/components/themed-view';
import { createLanguageScreenStyles } from '@/styles/language-screen.styles';

type Language = 'en' | 'ru' | 'uk' | 'be' | 'ro';

const FLAGS = {
  en: require('@/assets/images/flags/gb.webp'),
  ru: require('@/assets/images/flags/ru.webp'),
  uk: require('@/assets/images/flags/ua.webp'),
  be: require('@/assets/images/flags/by.webp'),
  ro: require('@/assets/images/flags/ro.webp'),
};

const LANGUAGES: { code: Language; name: string; nativeName: string }[] = [
  { code: 'en', name: 'English', nativeName: 'English' },
  { code: 'uk', name: 'Ukrainian', nativeName: 'Українська' },
  { code: 'ro', name: 'Romanian', nativeName: 'Română' },
  { code: 'ru', name: 'Russian', nativeName: 'Русский' },
  { code: 'be', name: 'Belarusian', nativeName: 'Беларуская' },
];

export default function LanguageSelectionScreen() {
  const styles = createLanguageScreenStyles();
  const { locale, setLocale } = useI18n();

  const handleSelectLanguage = (code: Language) => {
    setLocale(code);
  };

  return (
    <ThemedView style={styles.container}>
      <FlashList
        data={LANGUAGES}
        keyExtractor={(item) => item.code}
        estimatedItemSize={86}
        showsVerticalScrollIndicator={false}
        contentContainerStyle={styles.content}
        ItemSeparatorComponent={() => <View style={styles.itemSeparator} />}
        renderItem={({ item: lang }) => {
          const isSelected = locale === lang.code;
          return (
            <SelectionItem
              title={lang.nativeName}
              selected={isSelected}
              onPress={() => handleSelectLanguage(lang.code)}
              leftAccessory={
                <View style={styles.flagBadge}>
                  <Image
                    source={FLAGS[lang.code]}
                    style={styles.flagImage}
                    contentFit="cover"
                    transition={0}
                    cachePolicy="memory-disk"
                  />
                </View>
              }
            />
          );
        }}
      />
    </ThemedView>
  );
}
