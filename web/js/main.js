// Main Application

class VisualGuideApp {
    constructor() {
        this.camera = new CameraService();
        this.location = new LocationService();
        this.osm = new OSMService();

        this.isScanning = false;
        this.scanInterval = null;
        this.scanIntervalMs = 5000; // Scan every 5 seconds

        this.initializeUI();
    }

    /**
     * Initialize and auto-start
     */
    async initializeUI() {
        // Auto-start on load
        await this.start();
    }

    /**
     * Start the application automatically
     */
    async start() {
        try {
            log('Starting Visual Guide automatically...');
            updateUI('location-text', 'Getting location...');
            updateUI('api-text', 'Initializing...');

            // Initialize camera
            await this.camera.initialize();
            updateUI('api-text', 'Camera ready, getting location...');

            // Get initial location with retry
            let retries = 3;
            let loc = null;

            while (retries > 0 && !loc) {
                try {
                    await this.location.getCurrentPosition();
                    loc = this.location.getLastPosition();
                    if (loc) break;
                } catch (error) {
                    retries--;
                    if (retries > 0) {
                        log(`Location attempt failed, retrying... (${retries} left)`, 'warn');
                        await new Promise(resolve => setTimeout(resolve, 1000));
                    } else {
                        throw error;
                    }
                }
            }

            if (!loc) {
                throw new Error('Unable to get location after multiple attempts');
            }

            log(`Location acquired: ${loc.lat.toFixed(4)}, ${loc.lon.toFixed(4)}`);

            // Start continuous location tracking
            this.location.watchPosition((position) => {
                log(`Location updated: ${position.lat.toFixed(4)}, ${position.lon.toFixed(4)}`);
            });

            // Hide status overlay after successful initialization
            const statusOverlay = document.getElementById('status-overlay');
            if (statusOverlay) {
                statusOverlay.style.display = 'none';
            }

            // Enable scanning
            this.isScanning = true;

            log('Visual Guide started - scanning nearby locations every 5 seconds');

            // Start periodic scanning
            this.scanInterval = setInterval(() => this.scan(), this.scanIntervalMs);

            // Do first scan immediately
            await this.scan();

        } catch (error) {
            log(`Start error: ${error.message}`, 'error');
            updateUI('location-text', `Error: ${error.message}`);
            updateUI('api-text', 'Failed to start');
            alert(`Error: ${error.message}. Please grant camera and location permissions and reload the page.`);
        }
    }

    /**
     * Perform a single scan - get nearby locations
     */
    async scan() {
        if (!this.isScanning) return;

        try {
            log('--- Scanning nearby locations ---');

            // Get current location
            const location = this.location.getLastPosition();
            if (!location) {
                throw new Error('Location not available');
            }

            // Capture frame (for future use with YOLO)
            const frameBase64 = this.camera.captureFrame();

            // Get nearby POIs from OpenStreetMap
            const nearbyLocations = await this.osm.getLandmarksInBlock(location.lat, location.lon);

            // Update UI
            this.displayResults(nearbyLocations);

            log('--- Scan complete ---');

        } catch (error) {
            log(`Scan error: ${error.message}`, 'error');
        }
    }

    /**
     * Display nearby locations in UI
     */
    displayResults(nearbyLocations) {
        // Group by category
        const byCategory = {};
        nearbyLocations.forEach(poi => {
            if (!byCategory[poi.category]) {
                byCategory[poi.category] = [];
            }
            byCategory[poi.category].push(poi);
        });

        // Create display list
        const displayList = [];

        // Add category headers and items
        Object.keys(byCategory).forEach(category => {
            const items = byCategory[category].slice(0, 3); // Top 3 per category
            items.forEach(poi => {
                let label = `${poi.name}`;

                // Add type details
                if (poi.category === 'food' && poi.cuisine) {
                    label += ` (${poi.cuisine} ${poi.type})`;
                } else if (poi.category === 'shop' && poi.shopType) {
                    label += ` (${poi.shopType})`;
                } else if (poi.type && poi.type !== poi.category) {
                    label += ` (${poi.type})`;
                }

                // Add distance
                if (poi.distance) {
                    label += ` - ${Math.round(poi.distance)}m`;
                }

                displayList.push(label);
            });
        });

        addToList('landmarks-list', displayList);
        log(`Displayed ${nearbyLocations.length} nearby locations`);
    }

    /**
     * Stop the application
     */
    stop() {
        log('Stopping Visual Guide...');

        this.isScanning = false;

        if (this.scanInterval) {
            clearInterval(this.scanInterval);
            this.scanInterval = null;
        }

        this.camera.stop();
        this.location.stopWatching();

        log('Visual Guide stopped');
    }
}

// Initialize app when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    log('Visual Guide App loaded');
    window.app = new VisualGuideApp();
});
