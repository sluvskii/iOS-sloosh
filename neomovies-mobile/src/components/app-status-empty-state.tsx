import { CircleAlert, WifiOff, Wrench } from 'lucide-react-native';
import { View } from 'react-native';

import { ThemedText } from '@/components/themed-text';
import { useTheme } from '@/hooks/use-theme';
import { useI18n } from '@/i18n';
import { getOfflineModeSnapshot } from '@/lib/offline-mode';
import { appStatusEmptyStateStyles } from '@/styles/app-status-empty-state.styles';

type Props = {
  compact?: boolean;
};

export function AppStatusEmptyState({ compact = false }: Props) {
  const theme = useTheme();
  const { copy } = useI18n();
  const offline = getOfflineModeSnapshot();
  const reason = offline.reason;

  const isNetwork = reason === 'network';
  const title = isNetwork ? copy.appStatus.noInternetTitle : copy.appStatus.maintenanceTitle;
  const description = isNetwork ? copy.appStatus.noInternetDescription : copy.appStatus.maintenanceDescription;

  return (
    <View style={[appStatusEmptyStateStyles.container, compact ? appStatusEmptyStateStyles.compact : null]}>
      <View style={appStatusEmptyStateStyles.iconWrap}>
        {isNetwork ? (
          <WifiOff size={48} color={theme.accent} strokeWidth={2} />
        ) : reason === 'maintenance' ? (
          <Wrench size={48} color={theme.accent} strokeWidth={2} />
        ) : (
          <CircleAlert size={48} color={theme.accent} strokeWidth={2} />
        )}
      </View>
      <ThemedText style={appStatusEmptyStateStyles.title}>{title}</ThemedText>
      <ThemedText style={appStatusEmptyStateStyles.description}>{description}</ThemedText>
    </View>
  );
}
