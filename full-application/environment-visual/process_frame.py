#!/usr/bin/env python3
"""
Main orchestration script for processing camera frames.

This script:
1. Accepts a frame path as command-line argument
2. Calls Gemini to analyze the frame
3. Calls Fish Audio to convert text to speech
4. Returns JSON with audio file paths
"""

import sys
import os
import json
from pathlib import Path

# Import local modules
import generate_audio_script as gemini_module
import fish as fish_module


def process_frame(frame_path):
    """Process a single camera frame through the Gemini + Fish Audio pipeline.
    
    Args:
        frame_path: Path to the image frame to process
        
    Returns:
        dict: Result with audio paths or error message
    """
    result = {
        "success": False,
        "frame": frame_path,
        "audio_files": [],
        "error": None
    }
    
    # Step 1: Verify frame exists
    if not os.path.exists(frame_path):
        result["error"] = f"Frame not found: {frame_path}"
        return result
    
    print(f"Processing frame: {frame_path}")
    
    # Step 2: Analyze frame with Gemini
    print("Calling Gemini API...")
    conversational_text = gemini_module.gemini_text(frame_path)
    
    if not conversational_text:
        result["error"] = "Failed to generate text from Gemini"
        return result
    
    print(f"Gemini analysis complete: {len(conversational_text)} characters")
    result["text"] = conversational_text
    
    # Step 3: Convert text to speech with Fish Audio
    print("Calling Fish Audio API...")
    audio1_path, audio2_path = fish_module.get_fish_audio(conversational_text)
    
    if not audio1_path or not audio2_path:
        result["error"] = "Failed to generate audio from Fish Audio"
        return result
    
    print(f"Audio generation complete:")
    print(f"  - {audio1_path}")
    print(f"  - {audio2_path}")
    
    # Step 4: Return success
    result["success"] = True
    result["audio_files"] = [audio1_path, audio2_path]
    
    return result


def main():
    """Main entry point for command-line usage."""
    if len(sys.argv) < 2:
        print("Usage: python process_frame.py <frame_path>")
        print("Example: python process_frame.py media/frames/frame_0001.png")
        sys.exit(1)
    
    frame_path = sys.argv[1]
    
    # Make path absolute
    if not os.path.isabs(frame_path):
        frame_path = os.path.join(os.path.dirname(__file__), frame_path)
    
    # Process the frame
    result = process_frame(frame_path)
    
    # Output result as JSON for Flutter to parse
    print("\n" + "="*50)
    print("RESULT:")
    print(json.dumps(result, indent=2))
    print("="*50)
    
    # Exit with appropriate code
    sys.exit(0 if result["success"] else 1)


if __name__ == "__main__":
    main()
