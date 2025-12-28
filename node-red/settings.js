/**
 * Node-RED Settings for Boulder Home Automation
 * 
 * Documentation: https://nodered.org/docs/user-guide/runtime/configuration
 */

module.exports = {
    // Flow file settings
    flowFile: 'flows.json',
    
    // User directory (inside container)
    userDir: '/data',
    
    // Security
    adminAuth: {
        type: "credentials",
        users: [{
            username: process.env.NODE_RED_USERNAME || "admin",
            password: process.env.NODE_RED_PASSWORD_HASH || "$2b$08$somehashhere",
            permissions: "*"
        }]
    },
    
    // Enable projects feature
    editorTheme: {
        projects: {
            enabled: true
        },
        palette: {
            editable: true
        }
    },
    
    // Logging
    logging: {
        console: {
            level: "info",
            metrics: false,
            audit: false
        }
    },
    
    // Context storage (for persistent data)
    contextStorage: {
        default: "file",
        file: {
            module: "localfilesystem"
        }
    },
    
    // Function node settings
    functionGlobalContext: {
        // MQTT broker settings
        mqtt: {
            broker: process.env.MQTT_BROKER || "mosquitto",
            port: parseInt(process.env.MQTT_PORT) || 1883,
            username: process.env.MQTT_USERNAME,
            password: process.env.MQTT_PASSWORD
        },
        // PostgreSQL settings
        postgres: {
            host: process.env.POSTGRES_HOST || "postgres",
            port: parseInt(process.env.POSTGRES_PORT) || 5432,
            database: process.env.POSTGRES_DB || "homeautomation",
            user: process.env.POSTGRES_USER,
            password: process.env.POSTGRES_PASSWORD
        },
        // UniFi Protect settings
        unifi: {
            host: process.env.UNIFI_HOST || "192.168.10.49",
            username: process.env.UNIFI_USERNAME,
            password: process.env.UNIFI_PASSWORD,
            port: parseInt(process.env.UNIFI_PORT) || 443
        },
        // Abode settings
        abode: {
            username: process.env.ABODE_USERNAME,
            password: process.env.ABODE_PASSWORD
        }
    },
    
    // Export settings
    exportGlobalContextKeys: false,
    
    // Node settings
    functionExternalModules: true,
    
    // Editor settings
    httpAdminRoot: '/',
    httpNodeRoot: '/api',
    
    // HTTPS settings (disabled by default, use nginx for SSL)
    https: false,
    
    // Enable diagnostics endpoint
    diagnostics: {
        enabled: true,
        ui: true
    },
    
    // Rate limiting
    runtimeState: {
        enabled: false,
        ui: false
    }
}