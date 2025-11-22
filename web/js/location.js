// Location Service

class LocationService {
    constructor() {
        this.watchId = null;
        this.currentPosition = null;
    }

    /**
     * Get current GPS position (one-time)
     */
    async getCurrentPosition() {
        return new Promise((resolve, reject) => {
            if (!navigator.geolocation) {
                reject(new Error('Geolocation not supported by this browser'));
                return;
            }

            log('Getting current location...');

            const options = {
                enableHighAccuracy: true,
                timeout: 15000,  // Increased timeout to 15 seconds
                maximumAge: 0
            };

            navigator.geolocation.getCurrentPosition(
                (position) => {
                    this.currentPosition = {
                        lat: position.coords.latitude,
                        lon: position.coords.longitude,
                        accuracy: position.coords.accuracy
                    };

                    log(`Location acquired: ${this.currentPosition.lat.toFixed(6)}, ${this.currentPosition.lon.toFixed(6)} (±${Math.round(this.currentPosition.accuracy)}m)`);
                    resolve(this.currentPosition);
                },
                (error) => {
                    let errorMessage = 'Unknown location error';
                    switch (error.code) {
                        case error.PERMISSION_DENIED:
                            errorMessage = 'Location permission denied';
                            break;
                        case error.POSITION_UNAVAILABLE:
                            errorMessage = 'Location unavailable';
                            break;
                        case error.TIMEOUT:
                            errorMessage = 'Location request timed out';
                            break;
                    }
                    log(`Location error: ${errorMessage}`, 'error');
                    reject(new Error(errorMessage));
                },
                options
            );
        });
    }

    /**
     * Watch position with continuous updates
     */
    watchPosition(callback) {
        if (!navigator.geolocation) {
            throw new Error('Geolocation not supported');
        }

        log('Starting location watch...');

        this.watchId = navigator.geolocation.watchPosition(
            (position) => {
                this.currentPosition = {
                    lat: position.coords.latitude,
                    lon: position.coords.longitude,
                    accuracy: position.coords.accuracy
                };

                if (callback) {
                    callback(this.currentPosition);
                }
            },
            (error) => {
                log(`Location watch error: ${error.message}`, 'warn');
            },
            {
                enableHighAccuracy: true,
                maximumAge: 0
            }
        );
    }

    /**
     * Stop watching position
     */
    stopWatching() {
        if (this.watchId !== null) {
            navigator.geolocation.clearWatch(this.watchId);
            this.watchId = null;
            log('Location watch stopped');
        }
    }

    /**
     * Get last known position
     */
    getLastPosition() {
        return this.currentPosition;
    }
}
