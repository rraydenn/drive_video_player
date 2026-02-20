# Drive Video Player 🎬

Une application mobile Flutter permettant de se connecter de manière sécurisée à un compte Google et de lire en streaming les vidéos d'un dossier Google Drive spécifique.

## 🚀 Fonctionnalités
* **Authentification Sécurisée :** Connexion via Google OAuth 2.0.
* **Streaming Cloud :** Lecture directe des vidéos depuis Google Drive sans téléchargement préalable.
* **Lecteur Vidéo Avancé :** Interface utilisateur native (via Chewie) avec mode plein écran, barre de progression et réglage du volume.
* **Navigation Fluide :** Boutons "Suivant" et "Précédent" avec système de boucle (wrap-around) sur la liste de lecture.
* **Lecture Automatique (Autoplay) :** Compte à rebours de 5 secondes façon YouTube avant de passer à la vidéo suivante.
* **Mode Aléatoire (Shuffle) :** Crée une liste de lecture mélangée sans doublons.
* **Recherche et Tri :** Filtrage dynamique par titre, et tri par ordre alphabétique (A-Z, Z-A) ou par date de modification (Plus récent/Plus ancien).
* **Mode Sombre/Clair :** S'adapte automatiquement aux paramètres système de l'appareil.

## 🛠️ Installation & Configuration

Pour exécuter ce projet localement, vous devrez configurer vos propres identifiants Google Cloud.

1. Clonez ce dépôt.
2. Exécutez `flutter pub get` pour installer les dépendances.
3. À la racine du projet, créez un fichier nommé `.env`.
4. Ajoutez vos identifiants à l'intérieur du fichier `.env` :
   ```env
   WEB_CLIENT_ID=votre_client_id_google_web.apps.googleusercontent.com
   FOLDER_ID=l_id_de_votre_dossier_google_drive
   ```
5. Configurez l'empreinte SHA-1 de votre application Android sur la console Google Cloud.
6. Lancez l'application avec `flutter run`.

---

*Note: Ce README a été généré par une intelligence artificielle.*