from google import genai
from PIL import Image
import os
from dotenv import load_dotenv
import fish as fs

def gemini_text(frame_path):
    """Analyze an image frame using Gemini API and return conversational text.
    
    Args:
        frame_path: Path to the image frame to analyze
        
    Returns:
        str: Generated conversational text or None on error
    """
    load_dotenv()

    gemini_api = os.getenv("GEMINI_API_KEY")
    if not gemini_api:
        print("Error: GEMINI_API_KEY not found in environment")
        return None
    
    # Verify frame exists
    if not os.path.exists(frame_path):
        print(f"Error: Frame not found at {frame_path}")
        return None

    # Load the image using the Pillow (PIL) library
    try:
        sample_image = Image.open(frame_path)
    except Exception as e:
        print(f"Error loading image: {e}")
        return None

    # The client gets the API key from the environment variable `GEMINI_API_KEY`.
    client = genai.Client(api_key=gemini_api)

    prompt = """You are a highly perceptive and efficient descriptive guide. Your task is 
    to provide a real-time, evocative audio description of the user's immediate surroundings. 
    The description must be delivered in a factual, stylish, and engaging manner, focusing 
    strictly on objects and elements that define the space.
    The entire description must be extremely concise—no more than a few seconds of spoken 
    word—to keep pace with the user's continuous movement.
    Describe the most striking, movable, or defining elements in the foreground (within three 
    steps) and the middle distance (up to 15 steps). Focus on textures, dominant colors, 
    and distinctive shapes of objects, people, or structures. Conclude with a single, 
    memorable summary of the current ambient feeling or setting (e.g., 'A lively outdoor 
    market,' 'The solemn geometry of office buildings'). Do NOT mention the weather, sky, or 
    any safety/navigational concerns.
    Create like a semi informal tone like a guide you know very well and is friendly. Don't begin with a greeting.

    If I have given you an image before and it is basically the same frame with very few changes 
    (like as if the user walked only a few steps ahead), then make a general comment, return 
    lesser text than usual and dont mention things you have mentioned before like how a 
    particular thing looks."""

    try:
        response = client.models.generate_content(
            model="gemini-2.5-flash", 
            contents=[
                sample_image,
                prompt
            ]
        )
        
        if response.text:
            print(f"Gemini response: {response.text[:100]}...")
            return response.text
        else:
            print("Error: Empty response from Gemini")
            return None
            
    except Exception as e:
        print(f"Error calling Gemini API: {e}")
        return None

if __name__ == "__main__":
    # Example usage for testing
    test_frame = './media/frames/frame_0001.png'
    if os.path.exists(test_frame):
        result = gemini_text(test_frame)
        if result:
            print(f"Generated text: {result}")
            # Optionally convert to audio
            # fs.get_fish_audio(result)

