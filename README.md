# Line of Sight

**Line of Sight** is an application designed to provide visual guidance and environmental context to visually-impaired people using advanced AI. The app integrates OpenStreetMap's Overpass API for local POI discovery, Google's Gemini API for real-time image analysis and conversational text generation, and Fish Audio's API for natural text-to-speech audio output.

## Features

*   **Real-time Object Detection**: Uses YOLOv8 to detect objects and identify potential hazards.
*   **Environmental Description**: Captures scenes and uses Google's Gemini AI Model to describe the surroundings in conversational text.
*   **POI Discovery**: Identifies nearby Points of Interest (POIs) using OpenStreetMap data and uses Google's Gemini AI Model to describe the POIs in conversational text.
*   **Audio Guidance**: Converts visual and location conversational text into audio using Fish Audio's API.
*   **Safety Alerts**: Prioritizes critical danger warnings over other audio descriptions.

## Prerequisites

Before running the application, ensure you have the following installed:

*   **Flutter SDK**: [Install Flutter](https://docs.flutter.dev/get-started/install)
*   **Python 3.8+**: [Install Python](https://www.python.org/downloads/)
*   **API Keys**:
    *   **Google Gemini API Key**: [Get Key](https://ai.google.dev/)
    *   **Fish Audio API Key**: [Get Key](https://fish.audio/)

## Installation

1.  **Clone the Repository**
    ```bash
    git clone https://github.com/arvindm84/Line-of-Sight
    cd MadHacks
    ```

2.  **Setup Environment Variables**
    *   Navigate to the `full-application` directory.
    *   Create a file named `.env`.
    *   Add your API keys:
        ```env
        GEMINI_API_KEY="your_gemini_api_key_here"
        FISH_AUDIO_API_KEY="your_fish_audio_api_key_here"
        ```

3.  **Install Python Dependencies**
    *   Navigate to the `environment-visual` directory:
        ```bash
        cd full-application/environment-visual
        ```
    *   Install the required packages:
        ```bash
        pip install -r requirements.txt
        ```

4.  **Install Flutter Dependencies**
    *   Navigate back to the `full-application` directory:
        ```bash
        cd ../
        ```
    *   Get the Flutter packages:
        ```bash
        flutter pub get
        ```

## Running the Application

1.  **Connect a Device**: Connect a physical Android/iOS device via cable, or start an emulator.
2.  **Run the App**:
    ```bash
    flutter run
    ```

## Usage

*   **Start/Stop**: Use the "Start Guiding" button to begin the video streaming and receive audio guidance.
*   **Safety**: The app will alert immediately if it detects hazards like cars or people in your path.
*   **Context**: Every 30 seconds, the app describes your visual surroundings. Every minute, the app recommends nearby places to visit and explore.
