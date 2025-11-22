// Camera Service

class CameraService {
    constructor() {
        this.stream = null;
        this.videoElement = document.getElementById('camera-feed');
        this.canvas = document.getElementById('capture-canvas');
        this.ctx = this.canvas.getContext('2d');
    }

    /**
     * Initialize camera and start video stream
     */
    async initialize() {
        try {
            log('Requesting camera access...');

            const constraints = {
                video: {
                    facingMode: 'environment', // Back camera on mobile
                    width: { ideal: 1280 },
                    height: { ideal: 720 }
                },
                audio: false
            };

            this.stream = await navigator.mediaDevices.getUserMedia(constraints);
            this.videoElement.srcObject = this.stream;

            log('Camera initialized successfully');
            return true;
        } catch (error) {
            log(`Camera error: ${error.message}`, 'error');
            throw new Error('Failed to access camera. Please grant camera permissions.');
        }
    }

    /**
     * Capture current frame as base64 image
     */
    captureFrame() {
        if (!this.stream) {
            throw new Error('Camera not initialized');
        }

        try {
            // Set canvas size to match video
            this.canvas.width = this.videoElement.videoWidth;
            this.canvas.height = this.videoElement.videoHeight;

            // Draw current video frame to canvas
            this.ctx.drawImage(this.videoElement, 0, 0);

            // Convert to base64 (JPEG, 80% quality for smaller size)
            const base64Image = this.canvas.toDataURL('image/jpeg', 0.8);

            log('Frame captured');
            return base64Image;
        } catch (error) {
            log(`Capture error: ${error.message}`, 'error');
            throw error;
        }
    }

    /**
     * Stop camera stream
     */
    stop() {
        if (this.stream) {
            this.stream.getTracks().forEach(track => track.stop());
            this.stream = null;
            log('Camera stopped');
        }
    }
}
