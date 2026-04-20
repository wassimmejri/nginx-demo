# Utilise l'image officielle légère de nginx
FROM nginx:alpine

# Expose le port 80 (le port par défaut de nginx)
EXPOSE 80

# Copie un fichier HTML personnalisé (optionnel)
# Si vous voulez une page d'accueil personnalisée, décommentez la ligne suivante
COPY index.html /usr/share/nginx/html/index.html
