import { Image } from 'expo-image';
import { useEffect, useMemo, useState } from 'react';
import { StyleProp, View, ViewStyle } from 'react-native';

import { ThemedView } from '@/components/themed-view';
import { mediaImageStyles } from '@/components/cards/media-image.styles';

type MediaImageProps = {
  primaryUri: string | null;
  fallbackUris?: (string | null | undefined)[];
  style?: StyleProp<ViewStyle>;
  imageKey?: string;
  priority?: 'low' | 'normal' | 'high';
};

const loadedUriMemory = new Set<string>();

export function MediaImage({ primaryUri, fallbackUris = [], style, imageKey, priority = 'normal' }: MediaImageProps) {
  const sourceList = useMemo(() => {
    const list = [primaryUri, ...fallbackUris].filter((item): item is string => Boolean(item));
    return Array.from(new Set(list));
  }, [fallbackUris, primaryUri]);
  const sourceKey = useMemo(() => sourceList.join('|'), [sourceList]);
  const [sourceIndex, setSourceIndex] = useState(0);
  const [loaded, setLoaded] = useState(() => {
    const firstUri = sourceList[0];
    return firstUri ? loadedUriMemory.has(firstUri) : false;
  });

  useEffect(() => {
    setSourceIndex(0);
    const firstUri = sourceList[0];
    setLoaded(firstUri ? loadedUriMemory.has(firstUri) : false);
  }, [sourceKey, sourceList]);

  const onImageError = () => {
    if (sourceIndex + 1 < sourceList.length) {
      setSourceIndex((value) => value + 1);
      setLoaded(false);
      return;
    }
    setLoaded(true);
  };

  const resolvedUri = sourceList[sourceIndex];
  const recyclingKey = imageKey ? `${imageKey}:${resolvedUri ?? 'empty'}` : resolvedUri ?? sourceKey;

  return (
    <View style={[mediaImageStyles.container, style]}>
      {resolvedUri ? (
        <Image
          key={recyclingKey}
          source={{ uri: resolvedUri }}
          recyclingKey={recyclingKey}
          style={mediaImageStyles.image}
          contentFit="cover"
          transition={0}
          cachePolicy="memory-disk"
          priority={priority}
          onLoad={() => {
            if (resolvedUri) loadedUriMemory.add(resolvedUri);
            setLoaded(true);
          }}
          onError={onImageError}
        />
      ) : null}

      {!loaded ? (
        <View style={mediaImageStyles.placeholder}>
          <ThemedView type="backgroundSelected" style={mediaImageStyles.image} />
        </View>
      ) : null}
    </View>
  );
}
