puts "Seeding Cinema App..."

user1 = User.find_or_create_by!(email: "ahmet@example.com") do |u|
  u.username = "ahmet_cine"
  u.password = "password123"
  u.password_confirmation = "password123"
end

user2 = User.find_or_create_by!(email: "merve@example.com") do |u|
  u.username = "merve_film"
  u.password = "password123"
  u.password_confirmation = "password123"
end

user3 = User.find_or_create_by!(email: "deniz@example.com") do |u|
  u.username = "deniz_scifi"
  u.password = "password123"
  u.password_confirmation = "password123"
end

# Seed Watchlists for user1
user1.watchlists.find_or_create_by!(tmdb_id: 157336, media_type: "movie") do |w|
  w.title = "Interstellar"
  w.poster_path = "/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg"
  w.status = :watched
  w.watched_at = 2.days.ago
  w.user_rating = 10
end

user1.watchlists.find_or_create_by!(tmdb_id: 872585, media_type: "movie") do |w|
  w.title = "Oppenheimer"
  w.poster_path = "/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg"
  w.status = :watched
  w.watched_at = 5.days.ago
  w.user_rating = 9
end

user1.watchlists.find_or_create_by!(tmdb_id: 693134, media_type: "movie") do |w|
  w.title = "Dune: Part Two"
  w.poster_path = "/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg"
  w.status = :plan_to_watch
end

user1.watchlists.find_or_create_by!(tmdb_id: 95557, media_type: "tv") do |w|
  w.title = "Severance"
  w.poster_path = "/3Pbt3qN6n40w2W1bKev14h6m92Z.jpg"
  w.status = :plan_to_watch
end

# Seed Community Post 1
post1 = user1.community_posts.find_or_create_by!(title: "Interstellar benzeri zihin yakan film önerisi?") do |p|
  p.content = "Zaman kırılmaları, evren teorileri veya derin felsefi alt metinleri olan filmleri çok seviyorum. Christopher Nolan yapımlarının neredeyse hepsini tükettim. Buna benzer atmosferi olan, soluksuz izlenecek yapımlar önerebilir misiniz?"
  p.tmdb_id = 157336
  p.media_type = "movie"
end

post1.community_replies.find_or_create_by!(user: user2, content: "Kesinlikle Denis Villeneuve'ün 'Arrival' (Geliş) filmini izlemelisin! Dilbilim ve zaman algısı üzerine muazzam bir başyapıt.")
post1.community_replies.find_or_create_by!(user: user3, content: "Biraz daha düşük bütçeli ama zihin yakan 'Coherence' (Paralel Evren) ve 'Primer' filmlerini de listene almalısın.")

# Seed Community Post 2
post2 = user2.community_posts.find_or_create_by!(title: "Severance 2. sezon öncesi hatırlanması gerekenler") do |p|
  p.content = "Lumon şirketinin gizemleri ve dış dünya ile iç benlik arasındaki bölünme hakkında ne düşünüyorsunuz? Final sahnesi beni haftalarca etkilemişti."
  p.tmdb_id = 95557
  p.media_type = "tv"
end

post2.community_replies.find_or_create_by!(user: user1, content: "Helly R.'nin gerçek kimliğinin ortaya çıktığı an dizinin zirve noktasıydı. 2. sezonu sabırsızlıkla bekliyorum!")

puts "Seeding completed successfully!"
