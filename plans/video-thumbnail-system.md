# Video Thumbnail Sistemi - Plan

## Özet
Story videoları için otomatik thumbnail oluşturma sistemi. Supabase Edge Function kullanarak videolardan frame çekme ve Storage'a kaydetme.

## Mevcut Durum
- `stories` tablosu `media_type` kolonu ile image/video ayrımı yapıyor
- Flutter tarafında `Story` modeli `isVideo` property'si var
- Story kartlarında video thumbnail gösterilmek isteniyor

## Adım 1: Database - thumbnail_url Alanı Ekleme

### Dosya: `supabase/migrations/20240123000008_add_story_thumbnail.sql`

```sql
-- Story tablosuna thumbnail_url alanı ekle
ALTER TABLE stories
ADD COLUMN IF NOT EXISTS thumbnail_url TEXT;

-- Index ekle
CREATE INDEX IF NOT EXISTS idx_stories_thumbnail_url ON stories(thumbnail_url);

-- Mevcut video story'ler için placeholder (opsiyonel)
-- UPDATE stories SET thumbnail_url = image_url || '-thumbnail.jpg' WHERE media_type = 'video' AND thumbnail_url IS NULL;
```

## Adım 2: Supabase Edge Function - Video Thumbnail Oluşturma

### Dosya: `supabase/functions/generate-video-thumbnail/index.ts`

```typescript
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// FFmpeg ile video thumbnail oluştur
const generateThumbnail = async (videoUrl: string, storagePath: string) => {
  // Videoyu indir
  const videoResponse = await fetch(videoUrl)
  const videoBuffer = await videoResponse.arrayBuffer()
  
  // FFmpeg komutu ile thumbnail oluştur
  const command = new Deno.Command('ffmpeg', {
    args: [
      '-i', 'pipe:0',           // stdin'den oku
      '-ss', '00:00:00.500',   // 0.5 saniyeden frame al
      '-vframes', '1',          // Sadece 1 frame
      '-vf', 'scale=300:-1',    // 300px genişlik, oran koru
      '-f', 'image2pipe',       // stdout'a image formatında yaz
      'pipe:1'                  // stdout'a yaz
    ],
    stdin: 'piped',
    stdout: 'piped',
  })
  
  const { stdout } = await command.spawn().output()
  
  // Thumbnail'ı Storage'a yükle
  const thumbnailPath = `${storagePath}-thumbnail.jpg`
  // ... upload kodu
  
  return thumbnailPath
}

serve(async (req) => {
  try {
    const { videoUrl, storyId } = await req.json()
    
    // Thumbnail oluştur
    const thumbnailPath = await generateThumbnail(videoUrl, `stories/${storyId}`)
    
    // Database'i güncelle
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )
    
    await supabase
      .from('stories')
      .update({ thumbnail_url: thumbnailPath })
      .eq('id', storyId)
    
    return new Response(JSON.stringify({ thumbnailPath }), {
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})
```

## Adım 3: Supabase Storage Trigger - Otomatik Thumbnail Tetikleme

### Dosya: `supabase/migrations/20240123000009_video_upload_trigger.sql`

```sql
-- Video yüklendiğinde otomatik thumbnail tetikleme
-- PostgreSQL Function
CREATE OR REPLACE FUNCTION trigger_video_thumbnail()
RETURNS TRIGGER AS $$
BEGIN
  -- Sadece video dosyaları için
  IF NEW.media_type = 'video' AND NEW.thumbnail_url IS NULL THEN
    -- Edge Function'ı asenkron çağır
    -- (Supabase'in http extension'ı gerekir)
    PERFORM net.http_post(
      format('%s/functions/v1/generate-video-thumbnail', current_setting('app.supabase_url')),
      json_build_object(
        'videoUrl', NEW.image_url,
        'storyId', NEW.id
      ),
      headers := json_build_object(
        'Authorization', 'Bearer ' || current_setting('app.supabase_anon_key')
      )
    );
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger oluştur
DROP TRIGGER IF EXISTS on_story_insert_trigger ON stories;
CREATE TRIGGER on_story_insert_trigger
  AFTER INSERT ON stories
  FOR EACH ROW
  EXECUTE FUNCTION trigger_video_thumbnail();
```

## Adım 4: Flutter - Story Model Güncelleme

### Dosya: `lib/core/models/post_model.dart`

```dart
class Story {
  final String id;
  final String userId;
  final String imageUrl;
  final String? thumbnailUrl;  // YENİ: Video thumbnail URL
  final bool isVideo;
  // ... diğer alanlar
  
  Story({
    required this.id,
    required this.userId,
    required this.imageUrl,
    this.thumbnailUrl,  // YENİ
    required this.isVideo,
    // ...
  });
  
  factory Story.fromJson(Map<String, dynamic> json) {
    return Story(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      imageUrl: json['image_url'] as String,
      thumbnailUrl: json['thumbnail_url'] as String?,  // YENİ
      isVideo: json['media_type'] == 'video' || json['is_video'] == true,
      // ...
    );
  }
}
```

## Adım 5: Flutter - Story Card Güncelleme

### Dosya: `lib/core/widgets/story_card.dart`

```dart
// Video thumbnail gösterimi
Image.network(
  story.isVideo 
      ? (story.thumbnailUrl ?? story.imageUrl)  // Önce thumbnail, yoksa video URL
      : story.imageUrl,
  fit: BoxFit.cover,
  errorBuilder: (context, error, stackTrace) {
    // Video ve thumbnail yoksa play ikonu
    if (story.isVideo) {
      return Container(
        color: Colors.grey.shade800,
        child: const Icon(
          Icons.play_circle_outline,
          size: 28,
          color: Colors.white54,
        ),
      );
    }
    // Resim hatalıysa image ikonu
    return Container(
      color: Colors.grey.shade300,
      child: const Icon(Icons.image, size: 24, color: Colors.grey),
    );
  },
)
```

## Adım 6: Alternatif Çözüm - Basit Approaches

### Seçenek A: Supabase Image Transformation Kullanım

```typescript
// Supabase Storage'nin image transformation özelliği
const thumbnailUrl = `${supabaseUrl}/storage/v1/render/image/public/${storageBucket}/${videoPath}?width=300&height=300&resize=cover`
```

### Seçenek B: Client-Side Video Player Widget

```dart
// Flutter'da VideoPlayer ile küçük widget
VideoPlayerController controller = VideoPlayerController.network(story.imageUrl);
controller.initialize();
VideoPlayerWidget(controller, size: Size(70, 70))
```

### Seçenek C: Üçüncü Parti Servis (Cloudinary, Mux)

```typescript
// Cloudinary auto thumbnail
const thumbnailUrl = `https://res.cloudinary.com/${cloudName}/video/upload/w_300,h_300,c_thumb/${videoPublicId}.jpg`
```

## Önerilen Implementasyon Sırası

1. **Hızlı Çözüm** (Bug fix): Önce client-side video widget ile göster
2. **Uzun Vadeli**: Supabase Edge Function ile otomatik thumbnail
3. **En İyi**: Supabase Image Transformation (Support kontrolü gerekli)

## Notlar

- FFmpeg Edge Function'da çalışmayabilir (Deno sınırlamaları)
- Alternatif: Cloudinary, Mux, veya Supabase Image Transformation
- En basit çözüm: Video yüklenirken client-side thumbnail oluşturup yüklemek
