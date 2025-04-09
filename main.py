import os
from app import app

if __name__ == "__main__":
    # En producción, desactivar debug mode y configurar para producción
    debug_mode = os.environ.get('FLASK_ENV') != 'production'
    
    app.run(
        host="0.0.0.0", 
        port=5000, 
        debug=debug_mode
    )
