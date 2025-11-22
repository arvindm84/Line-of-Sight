// OpenStreetMap Service

class OSMService {
    constructor() {
        this.nominatimEndpoint = 'https://nominatim.openstreetmap.org';
        this.overpassEndpoint = 'https://overpass-api.de/api/interpreter';
        this.cache = new Map();
        this.lastRequestTime = 0;
        this.minRequestInterval = 1000;
    }

    /**
     * Rate limiting helper
     */
    async waitForRateLimit() {
        const now = Date.now();
        const timeSinceLastRequest = now - this.lastRequestTime;

        if (timeSinceLastRequest < this.minRequestInterval) {
            const waitTime = this.minRequestInterval - timeSinceLastRequest;
            await new Promise(resolve => setTimeout(resolve, waitTime));
        }

        this.lastRequestTime = Date.now();
    }

    /**
     * Coordinates to address
     */
    async reverseGeocode(lat, lon) {
        const cacheKey = `reverse_${lat}_${lon}`;

        if (this.cache.has(cacheKey)) {
            log('Using cached reverse geocode');
            return this.cache.get(cacheKey);
        }

        try {
            await this.waitForRateLimit();

            log('Reverse geocoding...');

            const url = `${this.nominatimEndpoint}/reverse?` +
                `lat=${lat}&lon=${lon}&format=json&addressdetails=1`;

            const response = await fetch(url, {
                headers: {
                    'User-Agent': 'VisualGuideApp/1.0'
                }
            });

            if (!response.ok) {
                throw new Error(`Nominatim error: ${response.status}`);
            }

            const data = await response.json();

            const result = {
                address: data.display_name || 'Unknown location',
                city: data.address?.city || data.address?.town || data.address?.village,
                neighborhood: data.address?.neighbourhood || data.address?.suburb
            };

            this.cache.set(cacheKey, result);
            log(`Reverse geocode: ${result.address}`);

            return result;
        } catch (error) {
            log(`Reverse geocode error: ${error.message}`, 'error');
            return { address: 'Unknown location', city: null, neighborhood: null };
        }
    }

    /**
     * Get nearby Points of Interest using Overpass API
     */
    async getNearbyPOIs(lat, lon, radiusMeters = 100) {
        const cacheKey = `pois_${lat.toFixed(4)}_${lon.toFixed(4)}_${radiusMeters}`;

        if (this.cache.has(cacheKey)) {
            log('Using cached POIs');
            return this.cache.get(cacheKey);
        }

        try {
            log(`Querying POIs within ${radiusMeters}m...`);
            const query = `
                [out:json][timeout:25];
                (
                    node(around:${radiusMeters},${lat},${lon})["tourism"="attraction"];
                    way(around:${radiusMeters},${lat},${lon})["tourism"="attraction"];
                    node(around:${radiusMeters},${lat},${lon})["historic"];
                    way(around:${radiusMeters},${lat},${lon})["historic"];
                    node(around:${radiusMeters},${lat},${lon})["amenity"~"museum|theatre|cinema|library|restaurant|cafe|bar|pub|fast_food"];
                    way(around:${radiusMeters},${lat},${lon})["amenity"~"museum|theatre|cinema|library|restaurant|cafe|bar|pub|fast_food"];
                    node(around:${radiusMeters},${lat},${lon})["shop"];
                    way(around:${radiusMeters},${lat},${lon})["shop"];
                    node(around:${radiusMeters},${lat},${lon})["leisure"~"park|playground|garden"];
                    way(around:${radiusMeters},${lat},${lon})["leisure"~"park|playground|garden"];
                );
                out body;
                >;
                out skel qt;
            `;

            const response = await fetch(this.overpassEndpoint, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded'
                },
                body: `data=${encodeURIComponent(query)}`
            });

            if (!response.ok) {
                throw new Error(`Overpass error: ${response.status}`);
            }

            const data = await response.json();

            // Process results with categorization
            const pois = data.elements
                .filter(el => el.tags && el.tags.name)
                .map(el => {
                    let category = 'landmark';
                    if (el.tags.tourism) category = 'attraction';
                    else if (el.tags.historic) category = 'historic';
                    else if (el.tags.amenity === 'restaurant' || el.tags.amenity === 'cafe' || el.tags.amenity === 'bar') category = 'food';
                    else if (el.tags.shop) category = 'shop';
                    else if (el.tags.leisure) category = 'recreation';
                    else if (el.tags.amenity) category = 'amenity';

                    const type = el.tags.tourism ||
                        el.tags.historic ||
                        el.tags.amenity ||
                        el.tags.shop ||
                        el.tags.leisure ||
                        'landmark';

                    return {
                        name: el.tags.name,
                        category: category,
                        type: type,
                        cuisine: el.tags.cuisine,
                        shopType: el.tags.shop,
                        tags: el.tags,
                        lat: el.lat || el.center?.lat,
                        lon: el.lon || el.center?.lon,
                        distance: el.lat && el.lon ?
                            calculateDistance(lat, lon, el.lat, el.lon) : null
                    };
                })
                .sort((a, b) => (a.distance || 0) - (b.distance || 0));

            this.cache.set(cacheKey, pois);
            log(`Found ${pois.length} POIs (${this.categorizePOIs(pois)})`);

            return pois;
        } catch (error) {
            log(`POI query error: ${error.message}`, 'error');
            return [];
        }
    }

    /**
     * Categorize POIs for logging
     */
    categorizePOIs(pois) {
        const categories = {};
        pois.forEach(poi => {
            categories[poi.category] = (categories[poi.category] || 0) + 1;
        });
        return Object.entries(categories)
            .map(([cat, count]) => `${count} ${cat}`)
            .join(', ');
    }

    /**
     * Get landmarks within a city block (~100m)
     */
    async getLandmarksInBlock(lat, lon) {
        return this.getNearbyPOIs(lat, lon, 100);
    }
}
