import { Linking, Pressable, View } from 'react-native';
import { Code, Heart, Users } from 'lucide-react-native';
import { FlashList } from '@shopify/flash-list';

import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { useTheme } from '@/hooks/use-theme';
import { useI18n } from '@/i18n';
import { createCreditsScreenStyles } from '@/styles/credits-screen.styles';

const LIBRARIES = [
  { name: 'React Native', url: 'https://github.com/facebook/react-native' },
  { name: 'Expo', url: 'https://github.com/expo/expo' },
  { name: 'Expo Router', url: 'https://github.com/expo/expo/tree/main/packages/expo-router' },
  { name: 'Expo Image', url: 'https://github.com/expo/expo/tree/main/packages/expo-image' },
  { name: 'Expo AV', url: 'https://github.com/expo/expo/tree/main/packages/expo-av' },
  { name: 'ExoPlayer (Media3)', url: 'https://github.com/androidx/media' },
  { name: 'AVKit (iOS)', url: 'https://developer.apple.com/documentation/avkit' },
  { name: 'Lucide Icons', url: 'https://github.com/lucide-icons/lucide' },
  { name: 'Reanimated', url: 'https://github.com/software-mansion/react-native-reanimated' },
  { name: 'Tamagui', url: 'https://github.com/tamagui/tamagui' },
  { name: 'FlashList', url: 'https://github.com/Shopify/flash-list' },
  { name: 'React Query', url: 'https://github.com/TanStack/query' },
];

type TeamMemberKey = 'ernela' | 'chernuha' | 'iwnuply' | 'sophron';

const TEAM: { name: string; roleKey: TeamMemberKey; url: string }[] = [
  { name: 'Ernela', roleKey: 'ernela', url: 'https://github.com/Ernous' },
  { name: 'Chernuha', roleKey: 'chernuha', url: 'https://github.com/u1dm' },
  { name: 'IwnuplyNotTyan', roleKey: 'iwnuply', url: 'https://github.com/IwnuplyNotTyan' },
  { name: 'Sophron', roleKey: 'sophron', url: 'https://github.com/sophrosha' },
];

export default function CreditsScreen() {
  const theme = useTheme();
  const styles = createCreditsScreenStyles(theme);
  const { copy } = useI18n();

  const openUrl = (url: string) => {
    Linking.openURL(url).catch(() => {});
  };

  return (
    <ThemedView style={styles.container}>
      <FlashList
        data={[{ id: 'credits' }]}
        keyExtractor={(item) => item.id}
        estimatedItemSize={1200}
        showsVerticalScrollIndicator={false}
        renderItem={() => (
          <View style={styles.content}>
        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <Code size={20} color={theme.accent} />
            <ThemedText style={styles.sectionTitle}>{copy.credits.libraries}</ThemedText>
          </View>
          
          <View style={styles.creditsCard}>
            {LIBRARIES.map((lib, index) => (
              <Pressable 
                key={lib.name} 
                style={[styles.creditItem, index === LIBRARIES.length - 1 && styles.creditItemLast]}
                onPress={() => openUrl(lib.url)}
              >
                <ThemedText style={styles.creditName}>{lib.name}</ThemedText>
                <ThemedText style={[styles.creditDescription, { color: theme.accent }]}>
                  {lib.url.replace('https://github.com/', '').replace('https://', '')}
                </ThemedText>
              </Pressable>
            ))}
          </View>
        </View>

        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <Users size={20} color={theme.accent} />
            <ThemedText style={styles.sectionTitle}>{copy.credits.team}</ThemedText>
          </View>
          
          <View style={styles.creditsCard}>
            {TEAM.map((member, index) => (
              <Pressable 
                key={member.name}
                style={[styles.creditItem, index === TEAM.length - 1 && styles.creditItemLast]}
                onPress={() => openUrl(member.url)}
              >
                <ThemedText style={styles.creditName}>{member.name}</ThemedText>
                <ThemedText style={styles.creditDescription}>
                  {copy.credits.roles[member.roleKey]}
                </ThemedText>
              </Pressable>
            ))}
          </View>
        </View>

        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <Heart size={20} color={theme.accent} />
            <ThemedText style={styles.sectionTitle}>{copy.credits.thanks}</ThemedText>
          </View>
          
          <View style={styles.creditsCard}>
            <View style={[styles.creditItem, styles.creditItemLast]}>
              <ThemedText style={styles.creditName}>{copy.credits.community}</ThemedText>
              <ThemedText style={styles.creditDescription}>{copy.credits.madeWithLove}</ThemedText>
            </View>
          </View>
        </View>
          </View>
        )}
      />
    </ThemedView>
  );
}
