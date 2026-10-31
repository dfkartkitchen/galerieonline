// Konfigurace sdíleného sálu (Supabase). Postup je v SUPABASE-NAVOD.md, krok 5.
// Anon/publishable klíč je veřejný, data chrání RLS pravidla.
// NIKDY sem nedávejte service_role / Secret key.
// Prázdné hodnoty = galerie běží v místním režimu.
window.GALERIE_CONFIG = {
  supabaseUrl: "",
  supabaseAnonKey: ""
};
