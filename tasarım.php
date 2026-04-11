<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
    <title>CizreApp</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://unpkg.com/lucide@latest"></script>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;600;800;900&display=swap" rel="stylesheet">
    <style>
        /* ============================================== */
        /* 0. TEMA DEĞİŞKENLERİ */
        /* ============================================== */
        :root {
            --primary-color: #00C853; 
            --secondary-color: #00a844; 
            --sat-bottom: env(safe-area-inset-bottom, 60px); 
        }

        /* DİNAMİK RENKLER */
        .bg-primary { background-color: var(--primary-color); }
        .text-primary { color: var(--primary-color); }
        .border-primary { border-color: var(--primary-color); }
        
        /* ============================================== */
        /* 1. GÜVENLİ ALAN DEĞİŞKENLERİ */
        /* ============================================== */

        body { 
            font-family: 'Inter', sans-serif; 
            -webkit-tap-highlight-color: transparent;
            height: 100vh;
            height: 100dvh; 
            background-color: var(--primary-color);
        }
        .scrollbar-hide::-webkit-scrollbar { display: none; }
        .scrollbar-hide { -ms-overflow-style: none; scrollbar-width: none; }
        .fade-in { animation: fadeIn 0.3s ease-out forwards; }
        @keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
        @keyframes bounce-subtle {
            0%, 100% { transform: translateY(0); }
            50% { transform: translateY(-3px); }
        }
        .animate-bounce-subtle { animation: bounce-subtle 2s infinite; }
        .rating-star-fill { color: #FFC107; fill: #FFC107; }
        .rating-star-empty { color: #E0E0E0; fill: #E0E0E0; }

        /* ============================================== */
        /* 2. ALT NAVİGASYON ÇUBUĞU */
        /* ============================================== */
        #bottom-nav-wrapper {
            height: calc(70px + var(--sat-bottom));
            padding-bottom: var(--sat-bottom); 
            background-color: white; 
            pointer-events: none;
            z-index: 40; 
        }
        #btn-market.text-primary { color: var(--primary-color) !important; }
        #btn-market .bg-green-50 { background-color: rgba(0, 200, 83, 0.1) !important; }

        /* ============================================== */
        /* 3. ANA İÇERİK ALANI */
        /* ============================================== */
        #content-area {
            padding-bottom: calc(70px + var(--sat-bottom) + 32px) !important; 
        }

        /* ============================================== */
        /* 4. YÜZEN MESAJ BUTONU */
        /* ============================================== */
        #floating-msg-btn {
            bottom: calc(96px + var(--sat-bottom)); 
        }
        #floating-msg-btn .text-[#00C853] { color: var(--primary-color); }
    </style>
</head>
<body class="bg-primary h-screen w-screen overflow-hidden flex flex-col relative select-none">

    <div id="floating-msg-btn" class="fixed right-5 z-40 transition-all duration-300 transform scale-100" onclick="switchView('messages')">
        <div class="bg-white p-3 rounded-full shadow-lg border border-gray-100 relative hover:bg-gray-50 active:scale-95 transition-transform animate-bounce-subtle">
            <i data-lucide="message-circle" class="w-6 h-6 text-primary"></i>
            <span class="absolute top-0 right-0 bg-[#FF3D00] w-3.5 h-3.5 text-[9px] font-bold text-white flex items-center justify-center rounded-full border-2 border-white">1</span>
        </div>
    </div>

    <div id="search-overlay" class="fixed inset-0 bg-[#F5F7FA] z-[70] hidden flex-col animate-in fade-in duration-200">
        <div class="bg-white px-4 pb-4 shadow-sm flex items-center gap-3 pt-12">
            <div class="flex-1 bg-gray-100 rounded-xl flex items-center px-3 py-2.5">
                <i data-lucide="search" class="text-gray-400 w-5 h-5"></i>
                <input type="text" placeholder="Dükkan, yemek veya ürün ara..." class="bg-transparent border-none outline-none w-full ml-2 text-sm text-gray-700 placeholder-gray-400" autofocus>
            </div>
            <button onclick="toggleSearch(false)" class="text-primary font-bold text-sm">Vazgeç</button>
        </div>
        <div class="flex-1 overflow-y-auto p-6">
            <div class="mb-6">
                <div class="flex justify-between items-center mb-3">
                    <h3 class="text-sm font-bold text-gray-900">Son Aramalar</h3>
                    <span class="text-xs text-gray-400 cursor-pointer">Temizle</span>
                </div>
                <div class="space-y-3">
                    <div class="flex items-center justify-between text-gray-600">
                        <div class="flex items-center gap-3"><div class="bg-gray-100 p-2 rounded-full"><i data-lucide="clock" class="w-4 h-4 text-gray-400"></i></div><span class="text-sm">Nöbetçi Eczane</span></div>
                        <i data-lucide="x" class="w-4 h-4 text-gray-300"></i>
                    </div>
                    <div class="flex items-center justify-between text-gray-600">
                        <div class="flex items-center gap-3"><div class="bg-gray-100 p-2 rounded-full"><i data-lucide="clock" class="w-4 h-4 text-gray-400"></i></div><span class="text-sm">Lahmacun</span></div>
                        <i data-lucide="x" class="w-4 h-4 text-gray-300"></i>
                    </div>
                </div>
            </div>
            <div>
                <h3 class="text-sm font-bold text-gray-900 mb-3">Popüler</h3>
                <div class="flex flex-wrap gap-2">
                    <span class="bg-white border border-gray-200 px-3 py-1.5 rounded-full text-xs font-medium text-gray-600">Döner</span>
                    <span class="bg-white border border-gray-200 px-3 py-1.5 rounded-full text-xs font-medium text-gray-600">Teknoloji</span>
                    <span class="bg-white border border-gray-200 px-3 py-1.5 rounded-full text-xs font-medium text-gray-600">Cizrespor</span>
                </div>
            </div>
        </div>
    </div>

    <div id="notif-overlay" class="fixed inset-0 bg-black/50 z-50 hidden transition-opacity duration-300" onclick="toggleNotifications(false)"></div>
    <div id="notif-panel" class="fixed top-0 right-0 h-full w-[85%] max-w-sm bg-[#F5F7FA] z-[51] transform translate-x-full transition-transform duration-300 shadow-2xl flex flex-col">
        <div class="bg-white p-5 pt-12 shadow-sm flex items-center justify-between relative shrink-0">
            <h2 class="font-bold text-lg text-gray-800">Bildirimler</h2>
            <button onclick="toggleNotifications(false)" class="bg-gray-100 p-1.5 rounded-full"><i data-lucide="x" class="w-5 h-5 text-gray-500"></i></button>
        </div>
        <div class="flex-1 overflow-y-auto p-4 space-y-3">
            <div class="bg-white p-3 rounded-2xl shadow-sm border-l-4 border-primary flex gap-3">
                <div class="bg-green-50 p-2 rounded-full h-max"><i data-lucide="package-check" class="w-5 h-5 text-primary"></i></div>
                <div>
                    <h4 class="font-bold text-sm text-gray-800">Siparişin Teslim Edildi</h4>
                    <p class="text-xs text-gray-500 mt-0.5">Lezzet Durağı siparişiniz başarıyla teslim edildi.</p>
                    <span class="text-[10px] text-gray-400 mt-1 block">10 dk önce</span>
                </div>
            </div>
            <div class="bg-white p-3 rounded-2xl shadow-sm flex gap-3">
                <div class="bg-orange-50 p-2 rounded-full h-max"><i data-lucide="percent" class="w-5 h-5 text-orange-500"></i></div>
                <div>
                    <h4 class="font-bold text-sm text-gray-800">Büyük İndirim Başladı!</h4>
                    <p class="text-xs text-gray-500 mt-0.5">Tekno Cizre mağazasında %50'ye varan indirimleri kaçırma.</p>
                    <span class="text-[10px] text-gray-400 mt-1 block">2 saat önce</span>
                </div>
            </div>
        </div>
    </div>

    <div id="sidebar-overlay" class="fixed inset-0 bg-black/50 z-50 hidden transition-opacity duration-300" onclick="toggleSettings(false)"></div>
    <div id="sidebar-panel" class="fixed top-0 right-0 h-full w-[85%] max-w-sm bg-[#F5F7FA] z-[51] transform translate-x-full transition-transform duration-300 shadow-2xl flex flex-col">
        <div class="bg-primary p-6 text-white rounded-bl-[40px] shadow-md relative shrink-0">
            <button onclick="toggleSettings(false)" class="absolute top-5 right-5 bg-white/10 p-1 rounded-full"><i data-lucide="x" class="w-6 h-6"></i></button>
            <div class="flex items-center gap-4 mt-4">
                <div class="w-16 h-16 rounded-full border-4 border-white/30 overflow-hidden bg-gray-200">
                    <img src="https://images.unsplash.com/photo-1599566150163-29194dcaad36?auto=format&fit=crop&q=80&w=300&h=300" class="w-full h-full object-cover" alt="">
                </div>
                <div><h2 class="font-bold text-xl leading-none mb-1">Azad Cizreli</h2><p class="text-white/80 text-xs">CizreApp Üyesi</p></div>
            </div>
        </div>
        <div id="settings-dynamic-content" class="flex-1 overflow-y-auto p-6 space-y-2.5">
            </div>
    </div>

    <div class="shrink-0 px-6 pt-12 transition-all duration-300" id="main-header-container">
        <div class="flex justify-between items-center mb-4 transition-all duration-300" id="header-top-row">
            <h1 id="app-title" class="text-3xl font-extrabold text-white tracking-wide block">CizreApp</h1>
            
            <div id="sub-page-header" class="hidden items-center gap-3 text-white fade-in">
                <div onclick="switchView('market')" class="cursor-pointer bg-white/20 p-2 rounded-full hover:bg-white/30 transition-colors">
                    <i data-lucide="arrow-left" class="w-5 h-5"></i>
                </div>
                <div>
                   <h1 id="sub-page-title" class="text-xl font-bold tracking-wide leading-none">Başlık</h1>
                   <span id="sub-page-subtitle" class="text-xs text-white/80 font-medium">Alt Başlık</span>
                </div>
            </div>

            <div class="flex items-center gap-3.5">
                <div onclick="toggleSearch(true)" class="cursor-pointer hover:opacity-80 transition-opacity p-1">
                    <i data-lucide="search" class="text-white w-6 h-6"></i>
                </div>
                <div onclick="toggleNotifications(true)" class="relative cursor-pointer hover:opacity-80 p-1">
                    <i data-lucide="bell" class="text-white w-6 h-6"></i>
                    <span class="absolute -top-0.5 -right-0.5 bg-[#FF3D00] text-white text-[10px] font-bold w-4 h-4 flex items-center justify-center rounded-full border border-primary">2</span>
                </div>
                <div onclick="toggleSettings(true)" class="cursor-pointer hover:rotate-90 transition-transform duration-300 p-1">
                    <i data-lucide="settings" class="text-white w-6 h-6"></i>
                </div>
            </div>
        </div>

        <div id="stories-wrapper" class="transition-all duration-500 overflow-hidden max-h-[300px] opacity-100">
            <div id="stories-title-row" class="flex justify-between items-center mb-4">
                <p class="text-white/95 text-lg font-bold">Çevrende Neler Oluyor?</p>
            </div>
            <div id="stories-list" class="flex overflow-x-auto scrollbar-hide -mx-2 px-2 items-start transition-all duration-300 h-[220px] pb-6 gap-3"></div>
        </div>
    </div>

    <div class="flex-1 bg-[#F5F7FA] rounded-t-[40px] overflow-hidden relative shadow-[0_-10px_30px_rgba(0,0,0,0.15)] z-10 w-full">
        <div class="h-full overflow-y-auto scrollbar-hide w-full" id="content-area"></div>
    </div>

    <div id="bottom-nav-wrapper" class="absolute bottom-0 left-0 right-0 z-40">
        <div class="absolute top-0 w-full h-[70px] drop-shadow-[0_-5px_10px_rgba(0,0,0,0.05)]">
            <svg class="w-full h-full text-white fill-current" viewBox="0 0 375 70" preserveAspectRatio="none">
               <path d="M0,20 Q0,0 20,0 H128 Q148,0 158,15 Q168,35 187.5,35 Q207,35 217,15 Q227,0 247,0 H355 Q375,0 375,20 V70 H0 Z" />
            </svg>
        </div>
        <div class="relative flex justify-between items-end h-[70px] px-8 pb-4 max-w-md mx-auto pointer-events-auto">
            <button onclick="switchView('market')" id="btn-market" class="flex flex-col items-center gap-1 mb-1 transition-all text-primary -translate-y-1">
                <div class="p-1 rounded-full bg-green-50"><i data-lucide="store" class="w-[22px] h-[22px]" stroke-width="2.5"></i></div>
            </button>
            <button onclick="switchView('products')" id="btn-products" class="flex flex-col items-center gap-1 text-gray-400 mb-2 hover:text-primary transition-colors">
                <div class="p-1 rounded-full"><i data-lucide="shopping-bag" class="w-[22px] h-[22px]"></i></div>
            </button>
            <div class="absolute left-1/2 -translate-x-1/2 top-[-20px]">
                <button onclick="switchView('cart')" id="btn-cart-zap" class="w-14 h-14 bg-[#EEFF41] rounded-full flex items-center justify-center shadow-[0_8px_15px_rgba(238,255,65,0.4)] active:scale-95 transition-all border-4 border-[#F5F7FA] relative">
                    <i data-lucide="shopping-cart" class="w-7 h-7 text-black fill-black" id="cart-icon-main"></i>
                    <span id="cart-item-count" class="absolute -top-0.5 -right-0.5 bg-[#FF3D00] text-white text-[10px] font-bold w-4 h-4 flex items-center justify-center rounded-full border border-[#F5F7FA]">3</span>
                </button>
            </div>
            <button onclick="switchView('social')" id="btn-social" class="flex flex-col items-center gap-1 mb-2 transition-all text-gray-400">
                <div class="p-1 rounded-full"><i data-lucide="globe" class="w-[22px] h-[22px]"></i></div>
            </button>
            <button onclick="switchView('profile')" id="btn-profile" class="flex flex-col items-center gap-1 mb-2 transition-all text-gray-400">
                <div class="p-1 rounded-full"><i data-lucide="user" class="w-[22px] h-[22px]"></i></div>
            </button>
        </div>
    </div>

    <script>
        // --- TEMA VE GİZLİLİK DEĞİŞKENLERİ ---
        let currentTheme = 'green';
        const themes = {
            green: { primary: '#00C853', secondary: '#00a844' },
            blue: { primary: '#007AFF', secondary: '#0066cc' }
        };
        
        // --- VERİLER ---
        const stories = [
            { id: 1, user: 'Ablyn', time: '3 dk', img: 'https://images.unsplash.com/photo-1554118811-1e0d58224f24?w=350', title: '', btn: '', color: 'bg-[#7E57C2]', type: 'user' },
            { id: 2, user: 'Local Store', time: '', img: 'https://images.unsplash.com/photo-1441986300917-64674bd600d8?w=350', title: '', btn: '', color: 'bg-[#D4E157] text-black', type: 'live' },
            { id: 3, user: 'Yalım', time: '1 sa', img: 'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=350', title: '', btn: '', color: 'bg-[#D4E157] text-black', type: 'user' },
            { id: 4, user: 'Mem u Zin', time: '4 sa', img: 'https://images.unsplash.com/photo-1525507119028-ed4c629a60a3?w=350', title: '', btn: '', color: 'bg-[#7E57C2]', type: 'user' },
        ];

        const discounts = [
            { id: 1, title: "Kasap İndirimi", desc: "%20 İndirim", color: "bg-red-500", icon: "tag" },
            { id: 2, title: "Halk Ekmek", desc: "Taze Çıktı", color: "bg-orange-500", icon: "wheat" },
            { id: 3, title: "Manav Fırsatı", desc: "3 Al 2 Öde", color: "bg-green-500", icon: "apple" },
            { id: 4, title: "Teknoloji", desc: "Kulaklık Fırsatı", color: "bg-blue-500", icon: "headphones" }
        ];

        const shopCategories = [
            { id: 1, title: 'Market', count: '45', img: 'https://images.unsplash.com/photo-1542838132-92c53300491e?w=300' },
            { id: 2, title: 'Manav', count: '28', img: 'https://images.unsplash.com/photo-1610832958506-aa56368176cf?w=300' },
            { id: 3, title: 'Fırın & Tatlı', count: '32', img: 'https://images.unsplash.com/photo-1509440159596-0249088772ff?w=300' },
            { id: 4, title: 'Kuruyemiş', count: '15', img: 'https://images.unsplash.com/photo-1599577227786-89689531b464?w=300' },
        ];

        const news = [
             { id: 1, title: "Cizrespor'dan Yeni Transfer", src: "Spor", time: "2 sa", img: "https://images.unsplash.com/photo-1431324155629-1a6deb1dec8d?w=400&auto=format&fit=crop&q=60" },
             { id: 2, title: "Dicle Nehri Islah Çalışması Başladı", src: "Belediye", time: "5 sa", img: "https://images.unsplash.com/photo-1574068468668-a05a11f871da?w=400&auto=format&fit=crop&q=60" },
             { id: 3, title: "Sanat Sokağı Festivali Hazırlıkları", src: "Kültür", time: "1 gün", img: "https://images.unsplash.com/photo-1533174072545-e8d4aa97edf9?w=400&auto=format&fit=crop&q=60" }
        ];

        const fullScreenProducts = [
            { id: 1, shop: "Tekno Cizre", product: "iPhone 15 Pro Max 256GB", price: 85000, img: "https://images.unsplash.com/photo-1696446701796-da61225697cc?w=600&auto=format&fit=crop&q=60", desc: "Sınırlı stok, Cizre içi aynı gün teslimat.", rating: 4.8, reviews: 154 },
            { id: 2, shop: "Mem u Zin Butik", product: "Yazlık Keten Gömlek", price: 850, img: "https://images.unsplash.com/photo-1596755094514-f87e34085b2c?w=600&auto=format&fit=crop&q=60", desc: "Yeni sezon, %100 pamuklu kumaş.", rating: 4.2, reviews: 89 },
            { id: 3, shop: "Cizre Halı Sarayı", product: "El Dokuma Kilim", price: 3500, img: "https://images.unsplash.com/photo-1600166898405-da9535204843?w=600&auto=format&fit=crop&q=60", desc: "Otantik desenli, kök boya kilim.", rating: 5.0, reviews: 24 },
            { id: 4, shop: "Cizre Mobil", product: "Powerbank 20000mAh", price: 900, img: "https://images.unsplash.com/photo-1609091839311-d5365f9ff1c5?w=600&auto=format&fit=crop&q=60", desc: "Hızlı şarj özellikli, garantili.", rating: 3.9, reviews: 62 }
        ];

        const socialPosts = [
            { id: 1, user: 'Mehmet A.', loc: 'Mem u Zin Parkı', time: '15 dk', img: 'https://images.unsplash.com/photo-1566808985172-24b5a228394e?w=500', txt: 'Cizre parklarında bahar havası var! 🌸', likes: 124, comm: 18 },
            { id: 2, user: 'Cizre Gurme', loc: 'Sanat Sokağı', time: '45 dk', img: 'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?w=500', txt: 'Akşam yemeği için efsane bir sofra hazırladık. 🔥', likes: 342, comm: 56 }
        ];

        const myProfile = {
            name: 'Azad Cizreli', 
            handle: '@azadcizre73', 
            bio: 'Cizre sevdalısı 🏰 | Dijital İçerik Üreticisi 📸',
            avatar: 'https://images.unsplash.com/photo-1599566150163-29194dcaad36?w=300',
            banner: 'https://images.unsplash.com/photo-1626262963666-b32569c76629?w=800',
            isOnline: true,      
            isGhostMode: false,  
            posts: [
                { id: 101, user: 'Azad Cizreli', loc: 'El Cezeri Müzesi', time: '2 gün', img: 'https://images.unsplash.com/photo-1580540700028-21d125746781?w=500', txt: 'Cezeri\'nin torunlarıyız. 🤖⚙️', likes: 542, comm: 89 },
                { id: 102, user: 'Azad Cizreli', loc: 'Dicle Nehri', time: '1 hf', img: 'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=500', txt: 'Dicle\'de gün batımı... 🌅', likes: 320, comm: 45 }
            ]
        };

        const chatData = [
            { id: 1, user: 'Mem u Zin Butik', msg: 'Siparişiniz kargoya verildi. 📦', time: '2 dk', unread: 1, img: 'https://api.dicebear.com/7.x/avataaars/svg?seed=MemuZin', status: 'online' },
            { id: 2, user: 'Ahmet K.', msg: 'Yarın görüşürüz kardeşim.', time: '1 sa', unread: 0, img: 'https://api.dicebear.com/7.x/avataaars/svg?seed=Ahmet', status: 'offline' },
            { id: 3, user: 'Cizre Halı Sarayı', msg: 'Yeni sezon kilimlerimiz geldi.', time: '3 sa', unread: 2, img: 'https://api.dicebear.com/7.x/avataaars/svg?seed=Hali', status: 'online' },
            { id: 4, user: 'Ayşe T.', msg: 'Teşekkürler, çok beğendim.', time: 'Dün', unread: 0, img: 'https://api.dicebear.com/7.x/avataaars/svg?seed=Ayse', status: 'offline' }
        ];

        const cartItems = [
            { id: 1, product: "iPhone 15 Pro Max 256GB", shop: "Tekno Cizre", price: 85000, quantity: 1, img: "https://images.unsplash.com/photo-1696446701796-da61225697cc?w=600&auto=format&fit=crop&q=60" },
            { id: 2, product: "Yazlık Keten Gömlek", shop: "Mem u Zin Butik", price: 850, quantity: 2, img: "https://images.unsplash.com/photo-1596755094514-f87e34085b2c?w=600&auto=format&fit=crop&q=60" },
        ];
        
        const ordersData = [
            { id: 101, shop: "Tekno Cizre", date: "12 Aralık 2025", total: 85000, status: "Delivered", icon: "package-check", color: "text-[#00C853]", items: ["iPhone 15 Pro Max"] },
            { id: 102, shop: "Lezzet Durağı", date: "15 Aralık 2025", total: 150, status: "On its Way", icon: "bike", color: "text-orange-500", items: ["Lahmacun (2 adet)", "Ayran"] },
            { id: 103, shop: "Mem u Zin Butik", date: "10 Aralık 2025", total: 1700, status: "Cancelled", icon: "x-circle", color: "text-red-500", items: ["Yazlık Keten Gömlek (2 adet)"] },
        ];

        const paymentOptions = [
            { id: 'cod', name: 'Kapıda Ödeme (Nakit/Kart)', icon: 'wallet' },
            { id: 'online', name: 'Online Ödeme (Kredi/Banka Kartı)', icon: 'credit-card' },
        ];
        
        // --- FONKSİYONLAR ---
        let currentView = 'market';
        let selectedPayment = 'cod';

        function formatPrice(price) {
            return price.toLocaleString('tr-TR', { style: 'currency', currency: 'TRY', minimumFractionDigits: 0 });
        }

        function getCartTotal() {
            return cartItems.reduce((total, item) => total + (item.price * item.quantity), 0);
        }

        function updateCartBadges() {
            const count = cartItems.length;
            const badgeMain = document.getElementById('cart-item-count');
            const badgeSidebar = document.getElementById('cart-item-count-sidebar');
            
            if (badgeMain) badgeMain.innerText = count > 0 ? count : 0;
            if (badgeSidebar) badgeSidebar.innerText = count > 0 ? count : 0;

            if (count > 0) {
                if (badgeMain) badgeMain.classList.remove('hidden');
                if (badgeSidebar) badgeSidebar.classList.remove('hidden');
            } else {
                if (badgeMain) badgeMain.classList.add('hidden');
                if (badgeSidebar) badgeSidebar.classList.add('hidden');
            }
        }
        
        function renderRatingStars(rating, reviewCount) {
            const fullStars = Math.floor(rating);
            const hasHalfStar = rating % 1 !== 0;
            let html = '';

            for (let i = 0; i < 5; i++) {
                if (i < fullStars) {
                    html += `<i data-lucide="star" class="w-4 h-4 rating-star-fill fill-current"></i>`;
                } else if (i === fullStars && hasHalfStar) {
                    html += `<i data-lucide="star-half" class="w-4 h-4 rating-star-fill fill-current"></i>`;
                } else {
                    html += `<i data-lucide="star" class="w-4 h-4 rating-star-empty"></i>`;
                }
            }
            html += `<span class="text-xs text-gray-500 font-medium ml-1">(${reviewCount})</span>`;
            return html;
        }

        function toggleSettings(show) {
            const overlay = document.getElementById('sidebar-overlay');
            const panel = document.getElementById('sidebar-panel');
            if(show) { 
                renderSettingsPanel(); 
                overlay.classList.remove('hidden'); 
                panel.classList.remove('translate-x-full'); 
            } 
            else { 
                overlay.classList.add('hidden'); 
                panel.classList.add('translate-x-full'); 
            }
        }

        function toggleSearch(show) {
            const searchOverlay = document.getElementById('search-overlay');
            if(show) { 
                searchOverlay.classList.remove('hidden'); 
                searchOverlay.classList.add('flex');
            } else { 
                searchOverlay.classList.add('hidden'); 
                searchOverlay.classList.remove('flex');
            }
        }

        function toggleNotifications(show) {
            const overlay = document.getElementById('notif-overlay');
            const panel = document.getElementById('notif-panel');
            if(show) { overlay.classList.remove('hidden'); panel.classList.remove('translate-x-full'); } 
            else { overlay.classList.add('hidden'); panel.classList.add('translate-x-full'); }
        }

        function switchView(view) {
            currentView = view;
            renderHeader();
            renderStories();
            renderContent();
            updateNavStyles();
            lucide.createIcons();
        }

        function applyTheme(themeName) {
            currentTheme = themeName;
            const theme = themes[themeName];
            document.documentElement.style.setProperty('--primary-color', theme.primary);
            document.documentElement.style.setProperty('--secondary-color', theme.secondary);
            document.body.style.backgroundColor = theme.primary; 
        }

        function toggleTheme() {
            const newTheme = currentTheme === 'green' ? 'blue' : 'green';
            applyTheme(newTheme);
            renderSettingsPanel(); 
        }

        function renderHeader() {
            const appTitle = document.getElementById('app-title');
            const subPageHeader = document.getElementById('sub-page-header');
            const subPageTitle = document.getElementById('sub-page-title');
            const subPageSubtitle = document.getElementById('sub-page-subtitle');
            const storiesWrapper = document.getElementById('stories-wrapper');
            const headerContainer = document.getElementById('main-header-container');
            const floatingMsgBtn = document.getElementById('floating-msg-btn');
            const cartItemCount = cartItems.length;

            if(currentView === 'messages' || currentView === 'cart' || currentView === 'orders') {
                floatingMsgBtn.classList.add('scale-0');
            } else {
                floatingMsgBtn.classList.remove('scale-0');
            }

            if (currentView === 'profile' || currentView === 'messages' || currentView === 'cart' || currentView === 'orders') {
                appTitle.classList.add('hidden');
                subPageHeader.classList.remove('hidden');
                subPageHeader.classList.add('flex');
                
                if (currentView === 'profile') {
                    subPageTitle.innerText = "Azad Cizreli";
                    subPageSubtitle.innerText = myProfile.posts.length + " Gönderi";
                } else if (currentView === 'messages') {
                    const unreadCount = chatData.filter(c => c.unread > 0).length;
                    subPageTitle.innerText = "Mesajlar";
                    subPageSubtitle.innerText = unreadCount + " Okunmamış";
                } else if (currentView === 'cart') {
                    subPageTitle.innerText = "Sepetim";
                    subPageSubtitle.innerText = cartItemCount + " Ürün";
                } else if (currentView === 'orders') {
                    subPageTitle.innerText = "Siparişlerim";
                    subPageSubtitle.innerText = ordersData.length + " Sipariş";
                }

                storiesWrapper.classList.add('max-h-0', 'opacity-0');
                storiesWrapper.classList.remove('max-h-[300px]', 'opacity-100');
                headerContainer.classList.remove('pt-12');
                headerContainer.classList.add('pt-8');
            } else {
                appTitle.classList.remove('hidden');
                subPageHeader.classList.add('hidden');
                subPageHeader.classList.remove('flex');
                storiesWrapper.classList.remove('max-h-0', 'opacity-0');
                storiesWrapper.classList.add('max-h-[300px]', 'opacity-100');
                headerContainer.classList.add('pt-12');
                headerContainer.classList.remove('pt-8');
            }
        }

        function renderStories() {
            const list = document.getElementById('stories-list');
            const titleRow = document.getElementById('stories-title-row');

            if (currentView === 'market') {
                list.className = "flex overflow-x-auto scrollbar-hide -mx-2 px-2 items-start transition-all duration-300 h-[220px] pb-6 gap-3";
                titleRow.classList.remove('hidden', 'opacity-0');
                // Sadece profil görseli ve isim bilgisi kalacak şekilde temizlendi
                list.innerHTML = stories.map(s => `
                    <div class="relative flex-shrink-0 w-[140px] h-[200px] rounded-[24px] overflow-hidden shadow-lg bg-gray-800 animate-in fade-in">
                        <img src="${s.img}" class="w-full h-full object-cover opacity-90" alt="">
                        <div class="absolute inset-0 bg-gradient-to-t from-black/60 to-transparent"></div>
                        <div class="absolute top-3 left-3 flex items-center gap-2">
                            <div class="w-7 h-7 rounded-full border border-white/80 overflow-hidden"><img src="https://api.dicebear.com/7.x/avataaars/svg?seed=${s.user}" alt=""/></div>
                            <div class="flex flex-col"><span class="text-white text-[10px] font-bold truncate w-16">${s.user}</span><span class="text-white/70 text-[9px]">${s.time}</span></div>
                        </div>
                    </div>
                `).join('');
            } else {
                list.className = "flex overflow-x-auto scrollbar-hide -mx-2 px-2 items-start transition-all duration-300 h-[105px] pb-2 gap-2";
                titleRow.classList.add('hidden', 'opacity-0');
                let html = `
                    <div class="flex flex-col items-center gap-1.5 min-w-[72px]">
                        <div class="relative w-[68px] h-[68px] rounded-full border-2 border-dashed border-white/40 flex items-center justify-center bg-white/10">
                            <i data-lucide="plus" class="text-white w-6 h-6"></i>
                            <div class="absolute bottom-0 right-0 bg-white text-primary rounded-full p-0.5 border-2 border-primary"><i data-lucide="plus" class="w-2.5 h-2.5"></i></div>
                        </div>
                        <span class="text-white text-[11px] font-medium">Hikayem</span>
                    </div>`;
                html += stories.map(s => `
                    <div class="flex flex-col items-center gap-1.5 min-w-[72px]">
                        <div class="relative w-[68px] h-[68px] rounded-full p-[3px] ${s.type === 'live' ? 'bg-gradient-to-tr from-yellow-400 via-red-500 to-purple-500' : 'bg-gradient-to-tr from-[#D0FF00] to-primary'}">
                            <div class="w-full h-full rounded-full border-[3px] border-primary overflow-hidden bg-gray-800"><img src="${s.img}" class="w-full h-full object-cover" alt=""></div>
                        </div>
                        <span class="text-white text-[11px] font-medium truncate w-16 text-center">${s.user}</span>
                    </div>
                `).join('');
                list.innerHTML = html;
            }
        }

        function renderContent() {
            const area = document.getElementById('content-area');
            let html = '';

            if (currentView === 'market') {
                html = `
                    <div class="pt-6 px-6 fade-in">
                        <div class="bg-red-50 border border-red-100 rounded-2xl p-4 mb-6 flex items-center justify-between shadow-sm">
                            <div class="flex items-center gap-3">
                                <div class="bg-white p-2.5 rounded-full shadow-sm text-red-500 border border-red-100"><i data-lucide="pill" class="w-6 h-6"></i></div>
                                <div><h3 class="font-bold text-red-600 text-sm">Nöbetçi: Cizre Şifa Eczanesi</h3><p class="text-red-400 text-[11px] font-medium">Yafes Mah. • 200m uzakta</p></div>
                            </div>
                            <button class="bg-red-500 text-white p-2.5 rounded-xl shadow-md active:scale-95 transition-transform"><i data-lucide="phone" class="w-4 h-4"></i></button>
                        </div>

                        <div class="mb-6">
                            <h2 class="text-lg font-bold text-gray-800 mb-3">Günün Fırsatları 🔥</h2>
                            <div class="flex gap-3 overflow-x-auto scrollbar-hide pb-2">
                                ${discounts.map(d => `
                                    <div class="flex-shrink-0 w-36 h-24 ${d.color} rounded-2xl p-3 flex flex-col justify-between shadow-md text-white relative overflow-hidden group cursor-pointer">
                                        <div class="absolute -right-3 -bottom-3 text-white/20 group-hover:scale-110 transition-transform"><i data-lucide="${d.icon}" class="w-16 h-16"></i></div>
                                        <span class="font-bold text-sm z-10 leading-tight">${d.title}</span>
                                        <span class="text-[10px] font-medium bg-white/20 w-max px-2 py-0.5 rounded z-10">${d.desc}</span>
                                    </div>
                                `).join('')}
                            </div>
                        </div>

                        <div class="flex items-center justify-between mb-4">
                            <h2 class="text-xl font-extrabold text-gray-800">Kategoriler</h2>
                            <span class="text-xs font-bold text-gray-400">Tümü</span>
                        </div>
                        <div class="grid grid-cols-2 gap-4 pb-6">
                            ${shopCategories.map(c => `
                                <div class="relative h-24 rounded-[20px] overflow-hidden group shadow-sm bg-gray-100">
                                    <img src="${c.img}" class="absolute inset-0 w-full h-full object-cover" alt="">
                                    <div class="absolute inset-0 bg-black/40"></div>
                                    <div class="absolute inset-0 p-3 flex flex-col justify-end">
                                        <h3 class="text-white font-bold text-base leading-none mb-1">${c.title}</h3>
                                        <span class="text-white/80 text-[9px]">${c.count} Dükkan</span>
                                    </div>
                                </div>
                            `).join('')}
                        </div>

                        <div class="mt-2 pb-4">
                             <div class="flex items-center justify-between mb-4"><h2 class="text-lg font-bold text-gray-800">Cizre'den Haberler</h2><span class="text-xs text-gray-400 font-bold">Tümü</span></div>
                             <div class="space-y-3">
                                 ${news.map(n => `
                                     <div class="flex gap-3 bg-white p-2.5 rounded-2xl shadow-sm border border-gray-50 items-center">
                                         <div class="w-20 h-20 shrink-0 rounded-xl overflow-hidden bg-gray-200">
                                             <img src="${n.img}" class="w-full h-full object-cover" alt="">
                                         </div>
                                         <div class="flex-1 py-1">
                                             <span class="bg-blue-50 text-blue-600 text-[10px] font-bold px-2 py-0.5 rounded-full mb-1 inline-block">${n.src}</span>
                                             <h4 class="font-bold text-sm text-gray-900 leading-tight mb-1.5 line-clamp-2">${n.title}</h4>
                                             <div class="flex items-center gap-1 text-gray-400 text-[10px]">
                                                 <i data-lucide="clock" class="w-3 h-3"></i> ${n.time} önce
                                             </div>
                                         </div>
                                     </div>
                                 `).join('')}
                             </div>
                        </div>
                    </div>`;
            } else if (currentView === 'products') {
                html = `
                    <div class="pt-6 px-6 fade-in">
                        <div class="flex items-center justify-between mb-5"><h2 class="text-xl font-extrabold text-gray-800">Vitrin</h2><span class="text-xs font-bold text-gray-400">Keşfet</span></div>
                        <div class="grid grid-cols-2 gap-3 pb-4">
                            ${fullScreenProducts.map(p => `
                                <div class="bg-white rounded-[24px] p-2 shadow-sm border border-gray-100 flex flex-col">
                                    <div class="rounded-[20px] overflow-hidden bg-gray-50 aspect-square shadow-inner relative mb-2">
                                        <img src="${p.img}" class="w-full h-full object-cover" alt="">
                                        <div class="absolute top-2 right-2 bg-white/90 p-1.5 rounded-full shadow-sm"><i data-lucide="heart" class="w-4 h-4 text-gray-400"></i></div>
                                    </div>
                                    <div class="px-1 flex-1 flex flex-col">
                                        <div class="flex items-center justify-between">
                                            <div class="flex items-center gap-1.5 mb-1">
                                                <img src="https://api.dicebear.com/7.x/avataaars/svg?seed=${p.shop}" class="w-4 h-4 rounded-full bg-gray-100" alt="">
                                                <span class="text-[10px] text-gray-500 font-bold truncate">${p.shop}</span>
                                            </div>
                                            <div class="flex items-center">${renderRatingStars(p.rating, p.reviews)}</div>
                                        </div>
                                        <h3 class="font-bold text-gray-900 text-sm leading-tight line-clamp-2 mb-auto">${p.product}</h3>
                                        <div class="flex items-center justify-between mt-2 pt-2 border-t border-gray-50">
                                            <span class="text-primary font-black text-sm">${formatPrice(p.price)}</span>
                                            <button onclick="addToCart(${p.id}, '${p.product}', ${p.price})" class="bg-primary text-white p-1.5 rounded-lg shadow-md active:scale-95 transition-transform">
                                                <i data-lucide="shopping-cart" class="w-4 h-4"></i>
                                            </button>
                                        </div>
                                    </div>
                                </div>
                            `).join('')}
                        </div>
                    </div>`;
            } else if (currentView === 'social') {
                html = `
                    <div class="pt-6 px-6 fade-in">
                        <div class="flex items-center justify-between mb-5"><h2 class="text-xl font-extrabold text-gray-800">Cizre Akışı</h2><span class="text-xs font-bold text-gray-400">Yeni</span></div>
                        <div class="flex flex-col gap-5 pb-4">
                            ${socialPosts.map(p => `
                                <div class="bg-white rounded-[24px] p-4 shadow-sm border border-gray-100">
                                    <div class="flex items-center justify-between mb-3">
                                        <div class="flex items-center gap-3">
                                            <div class="w-10 h-10 rounded-full bg-gray-100 p-0.5"><img src="https://api.dicebear.com/7.x/avataaars/svg?seed=${p.user}" class="rounded-full" alt=""></div>
                                            <div><h4 class="font-bold text-gray-800 text-sm">${p.user}</h4><div class="flex items-center gap-1 text-[10px] text-gray-500"><i data-lucide="map-pin" class="w-3 h-3"></i><span>${p.loc}</span> • <span>${p.time}</span></div></div>
                                        </div>
                                        <i data-lucide="more-horizontal" class="text-gray-400 w-5 h-5"></i>
                                    </div>
                                    <div class="rounded-[20px] overflow-hidden mb-3 bg-gray-50"><img src="${p.img}" class="w-full h-auto" alt=""></div>
                                    <div class="flex items-center justify-between mb-2 px-1">
                                        <div class="flex gap-4 text-gray-500 text-xs font-bold">
                                            <button class="flex items-center gap-1.5 hover:text-red-500"><i data-lucide="heart" class="w-5 h-5"></i>${p.likes}</button>
                                            <button class="flex items-center gap-1.5 hover:text-blue-500"><i data-lucide="message-square" class="w-5 h-5"></i>${p.comm}</button>
                                        </div>
                                        <i data-lucide="share-2" class="text-gray-500 w-5 h-5"></i>
                                    </div>
                                    <p class="text-gray-600 text-xs px-1"><span class="font-bold text-gray-800 mr-1">${p.user}</span>${p.txt}</p>
                                </div>
                            `).join('')}
                        </div>
                    </div>`;
            } else if (currentView === 'profile') {
                html = `
                    <div class="w-full fade-in">
                        <div class="relative">
                            <div class="h-32 w-full bg-gray-300"><img src="${myProfile.banner}" class="w-full h-full object-cover" alt=""></div>
                            <div class="absolute -bottom-10 left-6"><div class="w-20 h-20 rounded-full border-4 border-[#F5F7FA] overflow-hidden shadow-md bg-white"><img src="${myProfile.avatar}" class="w-full h-full object-cover" alt=""></div></div>
                            <div class="flex justify-end pt-3 pr-6"><button class="border border-gray-300 rounded-full px-4 py-1.5 text-xs font-bold text-gray-700">Düzenle</button></div>
                        </div>
                        <div class="px-6 mt-3">
                            <h2 class="text-xl font-black text-gray-900 leading-tight">${myProfile.name}</h2>
                            <p class="text-gray-500 text-xs font-medium mb-3">${myProfile.handle}</p>
                            <p class="text-gray-700 text-sm mb-3">${myProfile.bio}</p>
                            <div class="flex items-center gap-4 text-xs text-gray-500 mb-4">
                                <div class="flex items-center gap-1"><i data-lucide="map-pin" class="w-3 h-3"></i>Cizre</div>
                                <div class="flex items-center gap-1"><i data-lucide="calendar" class="w-3 h-3"></i>2021</div>
                            </div>
                            <div class="flex gap-4 text-sm mb-6">
                                <div><span class="font-bold text-gray-900">245</span> <span class="text-gray-500">Takip</span></div>
                                <div><span class="font-bold text-gray-900">1890</span> <span class="text-gray-500">Takipçi</span></div>
                            </div>
                            <div class="flex border-b border-gray-200 mb-4 overflow-x-auto scrollbar-hide text-sm font-bold">
                                <button class="px-4 py-3 text-gray-900 relative">Gönderiler<div class="absolute bottom-0 left-0 right-0 h-1 bg-primary rounded-t-full"></div></button>
                                <button class="px-4 py-3 text-gray-500">Yanıtlar</button>
                                <button class="px-4 py-3 text-gray-500">Medya</button>
                            </div>
                            <div class="flex flex-col gap-5 pb-4">
                                ${myProfile.posts.map(p => `
                                    <div class="bg-white rounded-[24px] p-4 shadow-sm border border-gray-100">
                                        <div class="flex items-center gap-3 mb-2">
                                            <div class="w-10 h-10 rounded-full bg-gray-100 p-0.5"><img src="${myProfile.avatar}" class="w-full h-full rounded-full" alt=""></div>
                                            <div><h4 class="font-bold text-gray-800 text-sm">${p.user}</h4><div class="flex items-center gap-1 text-[10px] text-gray-500"><i data-lucide="map-pin" class="w-3 h-3"></i>${p.loc} • ${p.time}</div></div>
                                        </div>
                                        <p class="text-gray-800 text-sm mb-3">${p.txt}</p>
                                        <div class="rounded-[20px] overflow-hidden mb-3 bg-gray-50"><img src="${p.img}" class="w-full h-auto" alt=""></div>
                                        <div class="flex items-center gap-6 text-gray-500 text-xs">
                                            <span class="flex items-center gap-1"><i data-lucide="heart" class="w-4 h-4"></i>${p.likes}</span>
                                            <span class="flex items-center gap-1"><i data-lucide="message-square" class="w-4 h-4"></i>${p.comm}</span>
                                        </div>
                                    </div>
                                `).join('')}
                            </div>
                        </div>
                    </div>`;
            } else if (currentView === 'messages') {
                const visibleOnlineUsers = chatData.filter(c => c.status === 'online').length;
                let myStatusText = myProfile.isOnline ? (myProfile.isGhostMode ? 'Gizli' : 'Açık') : 'Kapalı';

                html = `
                    <div class="pt-6 px-6 fade-in">
                        <div class="flex items-center justify-between mb-5">
                            <h2 class="text-xl font-extrabold text-gray-800">Gelen Kutusu</h2>
                            <div class="flex items-center gap-2 text-xs font-bold text-gray-400 cursor-pointer hover:text-primary transition-colors">
                                <i data-lucide="circle-dot" class="w-3 h-3 ${visibleOnlineUsers > 0 ? 'text-primary fill-primary' : 'text-gray-400'}"></i>
                                <span>${visibleOnlineUsers} Çevrimiçi</span>
                            </div>
                        </div>
                        <div onclick="toggleSettings(true)" class="bg-white p-4 rounded-2xl shadow-sm border border-gray-100 mb-4 flex items-center justify-between cursor-pointer active:scale-[0.99] transition-transform">
                            <div class="flex items-center gap-4">
                                <div class="w-10 h-10 rounded-full bg-gray-100 p-0.5"><img src="${myProfile.avatar}" class="rounded-full w-full h-full object-cover" alt=""></div>
                                <div>
                                    <h4 class="font-bold text-gray-900 text-sm">Durumun</h4>
                                    <p class="text-xs ${myStatusText === 'Kapalı' ? 'text-red-500' : myStatusText === 'Gizli' ? 'text-indigo-500' : 'text-primary'} font-semibold">Görünürlük: ${myStatusText}</p>
                                </div>
                            </div>
                            <i data-lucide="chevron-right" class="w-5 h-5 text-gray-400"></i>
                        </div>
                        <div class="space-y-4">
                            <div class="bg-white p-3 rounded-2xl flex items-center gap-3 shadow-sm border border-gray-50">
                                <i data-lucide="search" class="w-5 h-5 text-gray-400"></i>
                                <input type="text" placeholder="Mesajlarda ara..." class="w-full bg-transparent text-sm outline-none text-gray-600 placeholder-gray-400">
                            </div>
                            <div class="flex flex-col gap-2">
                                ${chatData.map(c => `
                                    <div class="bg-white p-4 rounded-2xl shadow-sm border border-gray-50 flex items-center gap-4 hover:bg-gray-50 transition-colors cursor-pointer">
                                        <div class="relative">
                                            <div class="w-14 h-14 rounded-full bg-gray-100 p-0.5"><img src="${c.img}" class="rounded-full w-full h-full object-cover" alt=""></div>
                                            ${c.status === 'online' ? '<div class="absolute bottom-0 right-0 w-3.5 h-3.5 bg-green-500 border-2 border-white rounded-full"></div>' : ''}
                                        </div>
                                        <div class="flex-1 min-w-0">
                                            <div class="flex justify-between items-center mb-1">
                                                <h4 class="font-bold text-gray-900 text-sm truncate">${c.user}</h4>
                                                <span class="text-[10px] ${c.unread > 0 ? 'text-green-600 font-bold' : 'text-gray-400'}">${c.time}</span>
                                            </div>
                                            <p class="text-xs ${c.unread > 0 ? 'text-gray-800 font-semibold' : 'text-gray-500'} truncate">${c.msg}</p>
                                        </div>
                                        ${c.unread > 0 ? `<div class="bg-red-500 text-white text-[10px] font-bold w-5 h-5 flex items-center justify-center rounded-full shadow-sm">${c.unread}</div>` : ''}
                                    </div>
                                `).join('')}
                            </div>
                        </div>
                    </div>`;
            } else if (currentView === 'cart') {
                const total = getCartTotal();
                html = `
                    <div class="pt-6 px-6 fade-in">
                        <div class="space-y-4">
                            ${cartItems.length > 0 ? cartItems.map(item => `
                                <div class="bg-white p-4 rounded-2xl shadow-sm border border-gray-100 flex items-center gap-4">
                                    <div class="w-16 h-16 rounded-xl overflow-hidden bg-gray-100 shrink-0">
                                        <img src="${item.img}" class="w-full h-full object-cover" alt="">
                                    </div>
                                    <div class="flex-1">
                                        <h4 class="font-bold text-gray-900 text-sm line-clamp-2">${item.product}</h4>
                                        <p class="text-xs text-gray-500">${item.shop}</p>
                                        <span class="text-[#FF3D00] font-bold text-sm block mt-1">${formatPrice(item.price)}</span>
                                    </div>
                                    <div class="flex flex-col items-end gap-1 shrink-0">
                                        <button onclick="removeFromCart(${item.id})" class="text-red-400 hover:text-red-600 active:scale-95 transition-transform"><i data-lucide="trash-2" class="w-4 h-4"></i></button>
                                        <div class="flex items-center border border-gray-200 rounded-lg">
                                            <button class="w-6 h-6 text-gray-500 hover:bg-gray-50 rounded-l-lg" onclick="updateQuantity(${item.id}, -1)"><i data-lucide="minus" class="w-4 h-4 mx-auto"></i></button>
                                            <span class="text-sm font-bold w-5 text-center">${item.quantity}</span>
                                            <button class="w-6 h-6 text-gray-500 hover:bg-gray-50 rounded-r-lg" onclick="updateQuantity(${item.id}, 1)"><i data-lucide="plus" class="w-4 h-4 mx-auto"></i></button>
                                        </div>
                                    </div>
                                </div>
                            `).join('') : `
                                <div class="text-center py-12 bg-white rounded-2xl shadow-sm border border-gray-100">
                                    <i data-lucide="shopping-cart" class="w-10 h-10 mx-auto text-gray-300 mb-3"></i>
                                    <h3 class="font-bold text-lg text-gray-700">Sepetiniz Boş</h3>
                                    <p class="text-sm text-gray-500 mt-1">Hemen alışverişe başlayın!</p>
                                </div>
                            `}
                        </div>
                        ${cartItems.length > 0 ? `
                            <div class="mt-6">
                                <h3 class="font-bold text-gray-800 text-md mb-3">Ödeme Yöntemi</h3>
                                <div class="space-y-2">
                                    ${paymentOptions.map(option => `
                                        <div onclick="setPaymentOption('${option.id}')" class="bg-white p-4 rounded-2xl shadow-sm border ${selectedPayment === option.id ? 'border-primary ring-2 ring-green-100' : 'border-gray-100'} flex items-center justify-between cursor-pointer active:scale-[0.99] transition-transform">
                                            <div class="flex items-center gap-3">
                                                <div class="p-2 rounded-full ${selectedPayment === option.id ? 'bg-green-50 text-primary' : 'bg-gray-100 text-gray-500'}"><i data-lucide="${option.icon}" class="w-5 h-5"></i></div>
                                                <span class="font-semibold text-sm text-gray-800">${option.name}</span>
                                            </div>
                                            ${selectedPayment === option.id ? '<i data-lucide="check-circle" class="w-5 h-5 text-primary fill-green-100"></i>' : '<div class="w-5 h-5 border border-gray-300 rounded-full"></div>'}
                                        </div>
                                    `).join('')}
                                </div>
                            </div>
                            <div class="mt-6 bg-white p-4 rounded-2xl shadow-md border border-gray-100">
                                <div class="flex justify-between items-center mb-3">
                                    <span class="text-gray-600 font-medium">Ara Toplam:</span>
                                    <span class="font-semibold text-gray-800">${formatPrice(total)}</span>
                                </div>
                                <div class="flex justify-between items-center border-t pt-3 border-gray-200">
                                    <span class="text-xl font-extrabold text-gray-900">GENEL TOPLAM:</span>
                                    <span class="text-xl font-extrabold text-primary">${formatPrice(total)}</span>
                                </div>
                            </div>
                            <button class="w-full bg-primary text-white py-3 rounded-xl font-bold text-lg mt-5 shadow-lg active:scale-95 transition-transform flex items-center justify-center gap-2">
                                <i data-lucide="check-circle" class="w-5 h-5"></i> Ödemeye Geç
                            </button>
                        ` : ''}
                    </div>
                `;
            } else if (currentView === 'orders') {
                html = `
                    <div class="pt-6 px-6 fade-in">
                        <div class="flex items-center justify-between mb-5">
                            <h2 class="text-xl font-extrabold text-gray-800">Geçmiş & Aktif Siparişler</h2>
                            <span class="text-xs font-bold text-gray-400">Arşiv</span>
                        </div>
                        <div class="space-y-4">
                            ${ordersData.map(order => `
                                <div class="bg-white p-4 rounded-2xl shadow-sm border border-gray-100 flex flex-col cursor-pointer hover:bg-gray-50 transition-colors">
                                    <div class="flex justify-between items-center mb-3 border-b border-dashed pb-3">
                                        <h4 class="font-bold text-gray-900 text-sm truncate">${order.shop}</h4>
                                        <span class="text-[10px] text-gray-500">${order.date}</span>
                                    </div>
                                    <div class="flex items-center gap-3">
                                        <div class="p-2 rounded-xl ${order.color.replace('text-', 'bg-')}/10 ${order.color}"><i data-lucide="${order.icon}" class="w-6 h-6"></i></div>
                                        <div class="flex-1 min-w-0">
                                            <h5 class="font-bold text-sm text-gray-800">${order.status === 'Delivered' ? 'Teslim Edildi' : order.status === 'On its Way' ? 'Yolda' : 'İptal Edildi'}</h5>
                                            <p class="text-xs text-gray-500 truncate">${order.items.join(', ')}</p>
                                        </div>
                                        <div class="flex flex-col items-end">
                                            <span class="font-extrabold text-sm text-primary">${formatPrice(order.total)}</span>
                                            <button class="text-blue-500 text-xs font-semibold mt-1">Detay</button>
                                        </div>
                                    </div>
                                </div>
                            `).join('')}
                        </div>
                    </div>
                `;
            }

            area.innerHTML = html;
        }

        function addToCart(id, product, price) {
            const existingItem = cartItems.find(item => item.id === id);
            if (existingItem) {
                existingItem.quantity++;
            } else {
                const productDetails = fullScreenProducts.find(p => p.id === id);
                cartItems.push({ 
                    id: id, 
                    product: product, 
                    shop: productDetails.shop, 
                    price: price, 
                    quantity: 1,
                    img: productDetails.img
                });
            }
            updateCartBadges();
            if (currentView === 'cart') renderContent();
            lucide.createIcons(); 
        }

        function removeFromCart(id) {
            const index = cartItems.findIndex(item => item.id === id);
            if (index !== -1) cartItems.splice(index, 1);
            updateCartBadges();
            if (currentView === 'cart') renderContent();
            lucide.createIcons();
        }

        function updateQuantity(id, change) {
            const item = cartItems.find(item => item.id === id);
            if (item) {
                item.quantity += change;
                if (item.quantity < 1) {
                    removeFromCart(id);
                    return;
                }
            }
            updateCartBadges();
            if (currentView === 'cart') renderContent();
            lucide.createIcons();
        }
        
        function setPaymentOption(optionId) {
            selectedPayment = optionId;
            if (currentView === 'cart') renderContent();
            lucide.createIcons();
        }

        function toggleOnlineVisibility(mode) {
            if (mode === 'ghost') {
                myProfile.isGhostMode = !myProfile.isGhostMode;
            } else if (mode === 'status') {
                myProfile.isOnline = !myProfile.isOnline;
                if (!myProfile.isOnline) myProfile.isGhostMode = false;
            }
            renderSettingsPanel(); 
            if (currentView === 'messages') switchView('messages'); 
            lucide.createIcons();
        }

        function renderSettingsPanel() {
            const settingsContent = document.getElementById('settings-dynamic-content');
            if (!settingsContent) return;

            settingsContent.innerHTML = `
                <div class="text-xs font-bold text-gray-400 uppercase tracking-wider mb-2 pl-1">Hesabım</div>
                <button onclick="switchView('cart'); toggleSettings(false);" class="w-full flex items-center justify-between p-4 bg-white rounded-2xl shadow-sm border border-gray-100 active:scale-95 transition-transform group">
                    <div class="flex items-center gap-4"><div class="bg-gray-50 text-gray-500 p-2 rounded-full group-hover:text-primary group-hover:bg-green-50 transition-colors"><i data-lucide="shopping-bag" class="w-5 h-5"></i></div><span class="font-bold text-gray-700 text-sm group-hover:text-primary">Sepetim</span></div>
                    <span id="cart-item-count-sidebar" class="bg-[#FF3D00] text-white text-xs font-bold px-2 py-0.5 rounded-full">${cartItems.length}</span>
                </button>
                <button onclick="switchView('profile'); toggleSettings(false)" class="w-full flex items-center justify-between p-4 bg-white rounded-2xl shadow-sm border border-gray-100 active:scale-95 transition-transform group">
                    <div class="flex items-center gap-4"><div class="bg-gray-50 text-gray-500 p-2 rounded-full group-hover:text-primary group-hover:bg-green-50 transition-colors"><i data-lucide="user" class="w-5 h-5"></i></div><span class="font-bold text-gray-700 text-sm group-hover:text-primary">Profilim</span></div>
                </button>
                <button onclick="switchView('orders'); toggleSettings(false)" class="w-full flex items-center justify-between p-4 bg-white rounded-2xl shadow-sm border border-gray-100 active:scale-95 transition-transform group">
                    <div class="flex items-center gap-4"><div class="bg-gray-50 text-gray-500 p-2 rounded-full group-hover:text-primary group-hover:bg-green-50 transition-colors"><i data-lucide="package" class="w-5 h-5"></i></div><span class="font-bold text-gray-700 text-sm group-hover:text-primary">Siparişlerim</span></div>
                </button>

                <div class="text-xs font-bold text-gray-400 uppercase tracking-wider mt-6 mb-2 pl-1">Gizlilik & Durum</div>

                <div onclick="toggleOnlineVisibility('status')" class="w-full flex items-center justify-between p-4 bg-white rounded-2xl shadow-sm border border-gray-100 cursor-pointer">
                    <div class="flex items-center gap-4">
                        <div class="bg-gray-50 text-gray-500 p-2 rounded-full ${myProfile.isOnline ? 'bg-green-50 text-primary' : ''}"><i data-lucide="circle-dot" class="w-5 h-5"></i></div>
                        <span class="font-bold text-gray-700 text-sm">Çevrimiçi Durumum: ${myProfile.isOnline ? 'Açık' : 'Kapalı'}</span>
                    </div>
                    <div class="${myProfile.isOnline ? 'bg-primary' : 'bg-gray-300'} w-10 h-6 rounded-full p-0.5 transition-colors">
                        <div class="bg-white w-5 h-5 rounded-full shadow-md transform ${myProfile.isOnline ? 'translate-x-4' : 'translate-x-0'} transition-transform"></div>
                    </div>
                </div>
                <div onclick="toggleOnlineVisibility('ghost')" class="w-full flex items-center justify-between p-4 bg-white rounded-2xl shadow-sm border border-gray-100 cursor-pointer ${!myProfile.isOnline ? 'opacity-50 pointer-events-none' : ''}">
                    <div class="flex items-center gap-4">
                        <div class="bg-gray-50 text-gray-500 p-2 rounded-full ${myProfile.isGhostMode ? 'bg-indigo-50 text-indigo-500' : ''}"><i data-lucide="eye-off" class="w-5 h-5"></i></div>
                        <span class="font-bold text-gray-700 text-sm">Hayalet Modu</span>
                    </div>
                    <div class="${myProfile.isGhostMode ? 'bg-indigo-500' : 'bg-gray-300'} w-10 h-6 rounded-full p-0.5 transition-colors">
                        <div class="bg-white w-5 h-5 rounded-full shadow-md transform ${myProfile.isGhostMode ? 'translate-x-4' : 'translate-x-0'} transition-transform"></div>
                    </div>
                </div>
                
                <div class="text-xs font-bold text-gray-400 uppercase tracking-wider mt-6 mb-2 pl-1">Görünüm</div>
                <div onclick="toggleTheme()" class="w-full flex items-center justify-between p-4 bg-white rounded-2xl shadow-sm border border-gray-100 cursor-pointer">
                    <div class="flex items-center gap-4">
                        <div class="bg-gray-50 text-gray-500 p-2 rounded-full"><i data-lucide="${currentTheme === 'green' ? 'sun' : 'moon'}" class="w-5 h-5"></i></div>
                        <span class="font-bold text-gray-700 text-sm">Tema: ${currentTheme === 'green' ? 'Yeşil' : 'Mavi'}</span>
                    </div>
                </div>
            `;
            lucide.createIcons();
        }

        function updateNavStyles() {
            const theme = themes[currentTheme];
            const primaryColor = theme.primary;
            const btns = { 
                market: document.getElementById('btn-market'), 
                products: document.getElementById('btn-products'),
                social: document.getElementById('btn-social'),
                profile: document.getElementById('btn-profile') 
            };
            const cartBtn = document.getElementById('btn-cart-zap');
            const cartIcon = document.getElementById('cart-icon-main');

            Object.values(btns).forEach(btn => { 
                if(btn) {
                    btn.classList.remove('text-primary', '-translate-y-1'); 
                    btn.style.color = 'rgb(156 163 175)';
                    btn.classList.add('text-gray-400');
                    btn.querySelector('div').style.backgroundColor = 'transparent';
                }
            });

            if(cartBtn) {
                cartBtn.style.backgroundColor = '#EEFF41';
                cartIcon.style.color = 'black';
                cartIcon.style.fill = 'black';
            }

            if(btns[currentView]) {
                btns[currentView].style.color = primaryColor;
                btns[currentView].classList.add('text-primary', '-translate-y-1');
                btns[currentView].querySelector('div').style.backgroundColor = primaryColor + '10';
            } else if (currentView === 'cart' && cartBtn) {
                cartBtn.style.backgroundColor = primaryColor;
                cartIcon.style.color = 'white';
                cartIcon.style.fill = 'white';
            }
        }

        window.onload = function() { 
            applyTheme('green');
            updateCartBadges();
            renderSettingsPanel(); 
            switchView('market'); 
        };
    </script>
</body>
</html>