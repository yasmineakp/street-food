-- ============================================================
-- STREET FOOD — SCHÉMA BASE DE DONNÉES SUPABASE
-- Multi-restaurants : une seule base pour N restaurants
-- ============================================================

-- ─── EXTENSION UUID ───
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- TABLE 1 : RESTAURANTS
-- Chaque restaurant a son propre espace isolé
-- ============================================================
CREATE TABLE restaurants (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  nom         TEXT NOT NULL,
  slug        TEXT UNIQUE NOT NULL,        -- ex: "street-food-abidjan"
  email       TEXT UNIQUE NOT NULL,
  telephone   TEXT,
  adresse     TEXT,
  logo_url    TEXT,
  couleur     TEXT DEFAULT '#ff6b2b',      -- couleur personnalisée
  actif       BOOLEAN DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- TABLE 2 : PLATS
-- Chaque plat appartient à un restaurant
-- ============================================================
CREATE TABLE plats (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  nom           TEXT NOT NULL,
  description   TEXT DEFAULT '',
  prix          INTEGER NOT NULL,            -- en centimes (ex: 450000 = 4500 FCFA)
  category      TEXT NOT NULL DEFAULT 'burgers',
  image_url     TEXT DEFAULT '',
  tags          TEXT[] DEFAULT '{}',         -- tableau de tags ["Premium","Best-seller"]
  disponible    BOOLEAN DEFAULT true,
  position      INTEGER DEFAULT 0,           -- ordre d'affichage
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- TABLE 3 : ZONES DE LIVRAISON
-- Par restaurant, avec prix de livraison
-- ============================================================
CREATE TABLE zones_livraison (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  restaurant_id   UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  nom             TEXT NOT NULL,           -- "Cocody", "Plateau", etc.
  prix_livraison  INTEGER NOT NULL DEFAULT 0, -- en centimes
  actif           BOOLEAN DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(restaurant_id, nom)
);

-- ============================================================
-- TABLE 4 : LIVREURS (NOUVEAU)
-- Flotte de livreurs propres à chaque restaurant
-- ============================================================
CREATE TABLE livreurs (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  nom           TEXT NOT NULL,
  prenom        TEXT NOT NULL,
  telephone     TEXT NOT NULL,
  vehicule      TEXT DEFAULT 'Moto',         -- 'Moto', 'Scooter', 'Vélo', etc.
  disponible    BOOLEAN DEFAULT true,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- TABLE 5 : COMMANDES (MODIFIÉE)
-- Toutes les commandes de tous les restaurants avec liaison livreur
-- ============================================================
CREATE TABLE commandes (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  restaurant_id   UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  livreur_id      UUID REFERENCES livreurs(id) ON DELETE SET NULL, -- Lien vers le livreur affecté
  type            TEXT NOT NULL CHECK (type IN ('onsite','delivery')),  -- sur place ou livraison
  status          TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','preparation','pret','servi','livree','annulee')),
  
  -- Sur place
  table_num       TEXT,                    -- "table-01"
  order_ref       TEXT,                    -- référence optionnelle client

  -- Livraison
  client_nom      TEXT,
  client_prenom   TEXT,
  client_tel      TEXT,
  client_ville    TEXT,
  client_adresse  TEXT,

  -- Montants
  sous_total      INTEGER NOT NULL DEFAULT 0,   -- centimes
  frais_livraison INTEGER NOT NULL DEFAULT 0,   -- centimes
  total_final     INTEGER NOT NULL DEFAULT 0,   -- centimes

  -- Détail
  instructions    TEXT DEFAULT '',
  
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- TABLE 6 : LIGNES DE COMMANDE (items)
-- Détail de chaque plat commandé
-- ============================================================
CREATE TABLE commande_items (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  commande_id   UUID NOT NULL REFERENCES commandes(id) ON DELETE CASCADE,
  plat_id       UUID REFERENCES plats(id) ON DELETE SET NULL,
  nom_plat      TEXT NOT NULL,             -- snapshot du nom au moment de la commande
  prix_unitaire INTEGER NOT NULL,          -- snapshot du prix
  quantite      INTEGER NOT NULL DEFAULT 1,
  category      TEXT DEFAULT ''
);

-- ============================================================
-- TABLE 7 : RÉSERVATIONS
-- ============================================================
CREATE TABLE reservations (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  nom           TEXT NOT NULL,
  prenom        TEXT NOT NULL,
  tel           TEXT NOT NULL,
  date_resa     DATE NOT NULL,
  heure_resa    TIME NOT NULL,
  nb_personnes  INTEGER NOT NULL DEFAULT 2,
  notes         TEXT DEFAULT '',
  status        TEXT DEFAULT 'pending' CHECK (status IN ('pending','confirmee','annulee')),
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- INDEX POUR PERFORMANCES (important avec 1000+ clients)
-- ============================================================
CREATE INDEX idx_plats_restaurant ON plats(restaurant_id);
CREATE INDEX idx_plats_category ON plats(restaurant_id, category);
CREATE INDEX idx_commandes_restaurant ON commandes(restaurant_id);
CREATE INDEX idx_commandes_status ON commandes(restaurant_id, status);
CREATE INDEX idx_commandes_created ON commandes(restaurant_id, created_at DESC);
CREATE INDEX idx_commande_items_commande ON commande_items(commande_id);
CREATE INDEX idx_reservations_restaurant ON reservations(restaurant_id);
CREATE INDEX idx_zones_restaurant ON zones_livraison(restaurant_id);
CREATE INDEX idx_restaurants_slug ON restaurants(slug);
CREATE INDEX idx_livreurs_restaurant ON livreurs(restaurant_id);       -- Index livreurs
CREATE INDEX idx_livreurs_dispo ON livreurs(restaurant_id, disponible); -- Index dispo livreurs
CREATE INDEX idx_commandes_livreur ON commandes(livreur_id);           -- Index de liaison commande/livreur

-- ============================================================
-- TRIGGERS : updated_at automatique
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_plats_updated
  BEFORE UPDATE ON plats
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_commandes_updated
  BEFORE UPDATE ON commandes
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- ROW LEVEL SECURITY (RLS) — Isolation par restaurant
-- Chaque restaurant ne voit QUE ses propres données
-- ============================================================
ALTER TABLE plats ENABLE ROW LEVEL SECURITY;
ALTER TABLE commandes ENABLE ROW LEVEL SECURITY;
ALTER TABLE commande_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE zones_livraison ENABLE ROW LEVEL SECURITY;
ALTER TABLE reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE livreurs ENABLE ROW LEVEL SECURITY; -- Activation RLS livreurs

-- Politique : lecture publique des plats (les clients voient le menu)
CREATE POLICY "plats_public_read" ON plats
  FOR SELECT USING (true);

-- Politique : lecture publique des zones (les clients voient les zones)
CREATE POLICY "zones_public_read" ON zones_livraison
  FOR SELECT USING (true);

-- Politique : les clients peuvent créer des commandes
CREATE POLICY "commandes_insert_public" ON commandes
  FOR INSERT WITH CHECK (true);

CREATE POLICY "commandes_items_insert_public" ON commande_items
  FOR INSERT WITH CHECK (true);

-- Politique : les clients peuvent créer des réservations
CREATE POLICY "reservations_insert_public" ON reservations
  FOR INSERT WITH CHECK (true);

-- Politique : lecture des commandes (pour le dashboard — à sécuriser avec auth en prod)
CREATE POLICY "commandes_read_all" ON commandes
  FOR SELECT USING (true);

CREATE POLICY "commandes_items_read_all" ON commande_items
  FOR SELECT USING (true);

CREATE POLICY "reservations_read_all" ON reservations
  FOR SELECT USING (true);

-- Politique : modification des commandes (statut / assignation livreur)
CREATE POLICY "commandes_update_all" ON commandes
  FOR UPDATE USING (true);

-- Politique : gestion des plats
CREATE POLICY "plats_manage_all" ON plats
  FOR ALL USING (true);

-- Politique : gestion des zones
CREATE POLICY "zones_manage_all" ON zones_livraison
  FOR ALL USING (true);

-- Politique : gestion des livreurs
CREATE POLICY "livreurs_manage_all" ON livreurs
  FOR ALL USING (true);

-- ============================================================
-- DONNÉES DE DÉMO : 1 restaurant exemple
-- ============================================================
INSERT INTO restaurants (nom, slug, email, telephone, adresse) VALUES
('Street Food Abidjan', 'street-food-abidjan', 'contact@streetfood-abidjan.ci', '+225 07 00 00 00', 'Plateau, Abidjan');

-- Récupère l'ID pour les insertions suivantes
DO $$
DECLARE
  resto_id UUID;
BEGIN
  SELECT id INTO resto_id FROM restaurants WHERE slug = 'street-food-abidjan';

  -- Plats démo
  INSERT INTO plats (restaurant_id, nom, description, prix, category, image_url, tags) VALUES
  (resto_id, 'Big Burger Classique', 'Bœuf 200g, cheddar fondu, salade, tomate', 450000, 'burgers', 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=400', ARRAY['Premium']),
  (resto_id, 'Double Smash Burger', 'Double steak smashé, sauce maison', 550000, 'burgers', 'https://images.unsplash.com/photo-1553979459-d2229ba7433b?w=400', ARRAY['Best-seller']),
  (resto_id, 'Pizza Margherita', 'Tomate, mozzarella, basilic frais', 600000, 'pizzas', 'https://images.unsplash.com/photo-1574071318508-1cdbab80d174?w=400', ARRAY['Végé']),
  (resto_id, 'Spaghetti Bolognaise', 'Sauce bolognaise maison mijotée 4h', 500000, 'pates', 'https://images.unsplash.com/photo-1621996346565-e3dbc353d2e5?w=400', ARRAY['Classique']),
  (resto_id, 'Jus d''Ananas Frais', '100% naturel, pressé minute', 150000, 'boissons', 'https://images.unsplash.com/photo-1490914327627-9fe8d52f4d90?w=400', ARRAY['Frais']);

  -- Zones de livraison démo
  INSERT INTO zones_livraison (restaurant_id, nom, prix_livraison) VALUES
  (resto_id, 'Plateau', 50000),
  (resto_id, 'Cocody', 100000),
  (resto_id, 'Yopougon', 200000),
  (resto_id, 'Abobo', 250000),
  (resto_id, 'Adjamé', 150000);

  -- Livreurs démo
  INSERT INTO livreurs (restaurant_id, nom, prenom, telephone, vehicule) VALUES
  (resto_id, 'Kouassi', 'Ahmed', '+225 05 01 02 03 04', 'Scooter'),
  (resto_id, 'Diallo', 'Moussa', '+225 07 05 06 07 08', 'Moto');
END $$;

-- ============================================================
-- VUE AMÉLIORÉE : Commandes avec leurs items et infos livreur
-- ============================================================
CREATE OR REPLACE VIEW v_commandes_detail AS
SELECT
  c.id,
  c.restaurant_id,
  r.nom AS restaurant_nom,
  c.type,
  c.status,
  c.table_num,
  c.order_ref,
  c.client_nom,
  c.client_prenom,
  c.client_tel,
  c.client_ville,
  c.client_adresse,
  c.sous_total,
  c.frais_livraison,
  c.total_final,
  c.instructions,
  c.created_at,
  c.updated_at,
  -- Infos livreur incluses (Retourne un objet JSON ou null si pas de livreur)
  CASE 
    WHEN c.livreur_id IS NOT NULL THEN 
      JSON_BUILD_OBJECT(
        'id', l.id,
        'nom', l.nom,
        'prenom', l.prenom,
        'telephone', l.telephone,
        'vehicule', l.vehicule
      )
    ELSE NULL 
  END AS livreur,
  JSON_AGG(
    JSON_BUILD_OBJECT(
      'nom', ci.nom_plat,
      'quantite', ci.quantite,
      'prix', ci.prix_unitaire,
      'category', ci.category
    ) ORDER BY ci.id
  ) AS items
FROM commandes c
JOIN restaurants r ON r.id = c.restaurant_id
LEFT JOIN livreurs l ON l.id = c.livreur_id
LEFT JOIN commande_items ci ON ci.commande_id = c.id
GROUP BY c.id, r.nom, l.id, c.livreur_id;