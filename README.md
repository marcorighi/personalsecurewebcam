Secure Image Capture and Monitoring Script

This Bash script is designed for secure image capture and monitoring using a webcam. It includes features for motion detection, image processing, and automated cleanup of old files.
Features

    Configuration:
        Output Directory: Specifies where captured images will be stored.
        Log File: Path to the log file for recording script activities.
        Frame Delay: Time delay between capturing frames.
        File Retention Days: Number of days to retain captured images before deletion.
        Image Format: Format of the captured images (e.g., jpg).
        Resolution: Resolution of the captured images.
        Fuzzy Value: Tolerance level for image comparison.
        Thresholds: Various thresholds for motion detection and image variation.

    Setup:
        Creates necessary directories and log files.
        Defines functions for logging and capturing frames using fswebcam.

    Temporary Files:
        Creates temporary files for storing the current and previous images, as well as their processed versions.

    Cleanup Mechanism:
        Periodically deletes old images based on the specified retention period.

    Dependency Check:
        Verifies the presence of required commands (fswebcam, compare, magick, bc).

    Motion Detection:
        Captures initial frame and logs the configuration.
        Continuously captures frames and processes them to detect motion.
        Uses ImageMagick to process and compare images.
        Maintains a buffer of recent variations to calculate average variation.
        Starts and stops capturing based on the calculated variation and predefined thresholds.

    Logging:
        Logs significant events, such as the start and stop of image capture, errors, and cleanup activities.

    Signal Handling:
        Handles script termination signals to ensure proper cleanup of temporary files.

marco.righi@cnr.it

