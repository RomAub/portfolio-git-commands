-- =====================================================================
--  TP Triggers - Gestion de stock "TechStock"
--  Rendu : tous les triggers finaux
--  Auteur : AUBREE Romain - BTS SIO SLAM - BTS Blanc 1
--  Base   : tp_triggers (MariaDB 10.4+)
--
--  Identite de TP :
--    N = 6   (nombre de lettres du nom AUBREE)
--    M = 12  (mois de naissance)
--    Initiale = R  ->  regle personnelle de la tranche Q-Z
--
--  Convention de nommage : trg_<table>_<b|a><i|u|d>
--    b = before / a = after ; i = insert / u = update / d = delete
-- =====================================================================

USE tp_triggers;

-- =====================================================================
--  PARTIE 2 - Triggers d'audit (table produit)
-- =====================================================================

-- 2.1  Tracer chaque creation de produit dans journal
DROP TRIGGER IF EXISTS trg_produit_ai;
DELIMITER $$
CREATE TRIGGER trg_produit_ai
AFTER INSERT ON produit
FOR EACH ROW
BEGIN
  INSERT INTO journal (utilisateur, table_cible, action, detail)
  VALUES (USER(), 'produit', 'INSERT',
          CONCAT('id=', NEW.id_produit, ' ; libelle=', NEW.libelle));
END$$
DELIMITER ;

-- 2.2  Historiser le prix s'il change, journaliser le stock s'il change
DROP TRIGGER IF EXISTS trg_produit_au;
DELIMITER $$
CREATE TRIGGER trg_produit_au
AFTER UPDATE ON produit
FOR EACH ROW
BEGIN
  IF NOT (OLD.prix_ht <=> NEW.prix_ht) THEN
    INSERT INTO historique_prix (id_produit, ancien_prix, nouveau_prix, utilisateur)
    VALUES (NEW.id_produit, OLD.prix_ht, NEW.prix_ht, USER());
  END IF;
  IF NOT (OLD.stock <=> NEW.stock) THEN
    INSERT INTO journal (utilisateur, table_cible, action, detail)
    VALUES (USER(), 'produit', 'UPDATE',
            CONCAT('stock ', OLD.stock, ' -> ', NEW.stock));
  END IF;
END$$
DELIMITER ;

-- 2.3  Tracer chaque suppression de produit dans journal
DROP TRIGGER IF EXISTS trg_produit_ad;
DELIMITER $$
CREATE TRIGGER trg_produit_ad
AFTER DELETE ON produit
FOR EACH ROW
BEGIN
  INSERT INTO journal (utilisateur, table_cible, action, detail)
  VALUES (USER(), 'produit', 'DELETE',
          CONCAT('id=', OLD.id_produit, ' ; libelle=', OLD.libelle));
END$$
DELIMITER ;

-- =====================================================================
--  PARTIE 3 - Triggers de controle (table produit)
-- =====================================================================

-- 3.1  Nettoyer et controler les donnees entrantes
DROP TRIGGER IF EXISTS trg_produit_bi;
DELIMITER $$
CREATE TRIGGER trg_produit_bi
BEFORE INSERT ON produit
FOR EACH ROW
BEGIN
  SET NEW.libelle = TRIM(NEW.libelle);
  IF NEW.libelle = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Libelle obligatoire';
  END IF;
  IF NEW.prix_ht <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Prix HT invalide (doit etre superieur a 0)';
  END IF;
  IF NEW.stock < 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stock negatif interdit';
  END IF;
END$$
DELIMITER ;

-- 3.2  Memes controles a la modification
DROP TRIGGER IF EXISTS trg_produit_bu;
DELIMITER $$
CREATE TRIGGER trg_produit_bu
BEFORE UPDATE ON produit
FOR EACH ROW
BEGIN
  SET NEW.libelle = TRIM(NEW.libelle);
  IF NEW.libelle = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Libelle obligatoire a la modification';
  END IF;
  IF NEW.prix_ht <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Prix invalide a la modification';
  END IF;
  IF NEW.stock < 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stock negatif interdit a la modification';
  END IF;
END$$
DELIMITER ;

-- =====================================================================
--  PARTIE 6.2 - Regle personnelle (initiale R, tranche Q-Z)
--  Interdire de supprimer un produit encore present
--  dans une commande au statut EN_COURS.
-- =====================================================================
DROP TRIGGER IF EXISTS trg_produit_bd;
DELIMITER $$
CREATE TRIGGER trg_produit_bd
BEFORE DELETE ON produit
FOR EACH ROW
BEGIN
  DECLARE v_nb INT;
  SELECT COUNT(*) INTO v_nb
  FROM ligne_commande l
  JOIN commande c ON c.id_commande = l.id_commande
  WHERE l.id_produit = OLD.id_produit
    AND c.statut = 'EN_COURS';
  IF v_nb > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Produit present dans une commande EN_COURS : suppression interdite';
  END IF;
END$$
DELIMITER ;

-- =====================================================================
--  PARTIE 4 - Triggers metier (table ligne_commande)
-- =====================================================================

-- 4.1  Controler la quantite et le stock, recopier le prix du produit
DROP TRIGGER IF EXISTS trg_ligne_bi;
DELIMITER $$
CREATE TRIGGER trg_ligne_bi
BEFORE INSERT ON ligne_commande
FOR EACH ROW
BEGIN
  DECLARE v_stock INT;
  DECLARE v_prix  DECIMAL(8,2);
  SELECT stock, prix_ht INTO v_stock, v_prix
  FROM produit
  WHERE id_produit = NEW.id_produit;
  IF NEW.quantite <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quantite invalide';
  END IF;
  IF v_stock < NEW.quantite THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stock insuffisant';
  END IF;
  SET NEW.prix_unitaire = v_prix;
END$$
DELIMITER ;

-- 4.2  Decrementer le stock et declencher l'alerte si besoin
DROP TRIGGER IF EXISTS trg_ligne_ai;
DELIMITER $$
CREATE TRIGGER trg_ligne_ai
AFTER INSERT ON ligne_commande
FOR EACH ROW
BEGIN
  DECLARE v_stock INT;
  DECLARE v_seuil INT;
  UPDATE produit
     SET stock = stock - NEW.quantite
   WHERE id_produit = NEW.id_produit;
  SELECT stock, seuil_alerte INTO v_stock, v_seuil
  FROM produit
  WHERE id_produit = NEW.id_produit;
  IF v_stock <= v_seuil THEN
    INSERT INTO alerte_stock (id_produit, stock_restant)
    VALUES (NEW.id_produit, v_stock);
  END IF;
END$$
DELIMITER ;

-- =====================================================================
--  PARTIE 5 - Triggers corriges (debogage)
-- =====================================================================

-- Correction 1 : NEW non modifiable en AFTER  ->  BEFORE INSERT
DROP TRIGGER IF EXISTS trg_client_bi;
DELIMITER $$
CREATE TRIGGER trg_client_bi
BEFORE INSERT ON client
FOR EACH ROW
BEGIN
  SET NEW.email = LOWER(NEW.email);
END$$
DELIMITER ;

-- Correction 3 : pas de NEW en DELETE  ->  OLD
DROP TRIGGER IF EXISTS trg_client_ad;
DELIMITER $$
CREATE TRIGGER trg_client_ad
AFTER DELETE ON client
FOR EACH ROW
BEGIN
  INSERT INTO journal (utilisateur, table_cible, action, detail)
  VALUES (USER(), 'client', 'DELETE', CONCAT('id=', OLD.id_client));
END$$
DELIMITER ;

-- Correction 2 : un trigger ne modifie pas sa table  ->  BEFORE UPDATE + SET NEW
DROP TRIGGER IF EXISTS trg_ligne_bu;
DELIMITER $$
CREATE TRIGGER trg_ligne_bu
BEFORE UPDATE ON ligne_commande
FOR EACH ROW
BEGIN
  IF NEW.quantite > 100 THEN
    SET NEW.quantite = 100;
  END IF;
END$$
DELIMITER ;

-- Correction 4 : restituer la vraie quantite (OLD.quantite) et non 1
DROP TRIGGER IF EXISTS trg_ligne_ad;
DELIMITER $$
CREATE TRIGGER trg_ligne_ad
AFTER DELETE ON ligne_commande
FOR EACH ROW
BEGIN
  UPDATE produit SET stock = stock + OLD.quantite WHERE id_produit = OLD.id_produit;
END$$
DELIMITER ;

-- =====================================================================
--  PARTIE 6.1 - Annulation et validation de commande (table commande)
-- =====================================================================
DROP TRIGGER IF EXISTS trg_commande_au;
DELIMITER $$
CREATE TRIGGER trg_commande_au
AFTER UPDATE ON commande
FOR EACH ROW
BEGIN
  -- Bloc 1 : annulation => on remet le stock
  IF OLD.statut <> 'ANNULEE' AND NEW.statut = 'ANNULEE' THEN
    UPDATE produit p
      JOIN ligne_commande l ON l.id_produit = p.id_produit
       SET p.stock = p.stock + l.quantite
     WHERE l.id_commande = NEW.id_commande;
  END IF;
  -- Bloc 2 : validation => on ajoute au total_achats du client la somme des lignes
  IF OLD.statut = 'EN_COURS' AND NEW.statut = 'VALIDEE' THEN
    UPDATE client c
       SET c.total_achats = c.total_achats + (
           SELECT COALESCE(SUM(l.quantite * l.prix_unitaire), 0)
             FROM ligne_commande l
            WHERE l.id_commande = NEW.id_commande)
     WHERE c.id_client = NEW.id_client;
  END IF;
END$$
DELIMITER ;

-- =====================================================================
--  Fin du rendu - 13 triggers
--  Verification : SHOW TRIGGERS;
-- =====================================================================
