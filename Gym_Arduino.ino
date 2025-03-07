#include <Arduino_LSM9DS1.h>
#include <ArduinoBLE.h>
#include <math.h>

// BLE service and characteristic declarations with intuitive names
BLEService gymService("19b9d254-3c2a-44b4-95d0-11746426f144");
BLEFloatCharacteristic rotationTotalCharacteristic("ff7f", BLERead | BLENotify);
BLEIntCharacteristic repCountCharacteristic("793d", BLERead | BLENotify);
BLEIntCharacteristic distanceCountCharacteristic("7a2e", BLERead | BLENotify);
BLEIntCharacteristic stepCountCharacteristic("8a1d", BLERead | BLENotify); 
BLEIntCharacteristic modeCharacteristic("330d", BLERead | BLEWrite);
BLEIntCharacteristic sessionStatusCharacteristic("a200", BLERead | BLEWrite);
BLEStringCharacteristic motionQualityCharacteristic("00a3", BLERead | BLENotify, 20);

// Global variables for overall state
float cumulativeRotationDegrees = 0.0;
int repCount = 0;       // repCount increases (each full rep is counted once)
int stepCount = 0;      // Step counter for Mode 4
int operationMode = 0;  // 0: idle; 1: rotation; 2: vertical pressing; 3: horizontal pressing; 4: step counter
int sessionStatus = 0;  // 0: not started; 1: started
String motionQualityString = "";
unsigned long previousTimeMicros = 0;

// Global variable to track last sent rep count (displayed value)
int lastSentReps = -1;

// Calibration state variables
bool calibrationDone = false;         // Flag indicating calibration is complete
unsigned long calibrationStartTime = 0; // When calibration waiting started

// Thresholds and constants for sensor processing
const float gyroscopeNoiseThreshold = 10.0;      // For rotation mode (degrees/sec)
const float rotationRepThresholdDegrees = 20.0;  // Rotation rep threshold (degrees)
const float accelerationNoiseThreshold = 0.1;     // For accelerometer (m/s²)
const float pressingRepThresholdDistance = 0.005;  // Pressing rep threshold (meters)
const unsigned long CALIBRATION_DELAY_MS = 5000;   // Wait 5 seconds for calibration
const unsigned long INACTIVITY_MS = 300;           // 300 ms inactivity threshold for peak-detection

// Variables for Rotation (Mode 1)
int rotationDirection = 0;
float accumulatedAngleDegrees = 0.0;

// Variables for Vertical Pressing (Mode 2)
float baselineY = 0.0;              // Baseline for Y-axis (calibrated)
float verticalTotalDistance = 0.0;  // Total vertical distance (m)
float verticalVelocity = 0.0;
float verticalRepDisplacement = 0.0; // Integrated displacement for rep counting
unsigned long verticalLastMotionMillis = 0;

// Variables for Horizontal Pressing (Mode 3)
float baselineX = 0.0;              // Baseline for X-axis (calibrated)
float horizontalTotalDistance = 0.0;  // Total horizontal distance (m)
float horizontalVelocity = 0.0;
float horizontalRepDisplacement = 0.0; // Integrated displacement for rep counting
unsigned long horizontalLastMotionMillis = 0;

// Variables for Step Counting (Mode 4)
const float stepThreshold = 1.0;         // Dynamic acceleration threshold (m/s²)
const float stepThresholdLow = 0.5;        // Lower threshold to reset detection
const unsigned long stepMinInterval = 300; // Minimum interval (ms) between steps

// Resets all integration, rep counting, and step counting variables.
void resetSession() {
  cumulativeRotationDegrees = 0;
  repCount = 0;
  stepCount = 0;
  lastSentReps = -1;
  rotationDirection = 0;
  accumulatedAngleDegrees = 0.0;
  verticalTotalDistance = 0.0;
  verticalVelocity = 0.0;
  verticalRepDisplacement = 0.0;
  horizontalTotalDistance = 0.0;
  horizontalVelocity = 0.0;
  horizontalRepDisplacement = 0.0;
  previousTimeMicros = micros();
  verticalLastMotionMillis = millis();
  horizontalLastMotionMillis = millis();
  calibrationDone = false;
  calibrationStartTime = millis();
  Serial.println("Session reset: All integration values cleared.");
}


// These functions average multiple readings to determine the sensor baseline.
void calibrateVerticalAxis() {
  float sum = 0;
  int count = 0;
  Serial.println("Calibrating Y-axis (vertical)... keep device still.");
  for (int i = 0; i < 100; i++) {
    float ax, ay, az;
    if (IMU.accelerationAvailable() && IMU.readAcceleration(ax, ay, az)) {
      sum += ay;
      count++;
    }
    delay(10);
  }
  if (count > 0) {
    baselineY = sum / count;
  }
  Serial.print("Calibrated baselineY: ");
  Serial.println(baselineY);
}

void calibrateHorizontalAxis() {
  float sum = 0;
  int count = 0;
  Serial.println("Calibrating X-axis (horizontal)... keep device still.");
  for (int i = 0; i < 100; i++) {
    float ax, ay, az;
    if (IMU.accelerationAvailable() && IMU.readAcceleration(ax, ay, az)) {
      sum += ax;
      count++;
    }
    delay(10);
  }
  if (count > 0) {
    baselineX = sum / count;
  }
  Serial.print("Calibrated baselineX: ");
  Serial.println(baselineX);
}

// BLE Event Handlers
void onModeWritten(BLEDevice central, BLECharacteristic characteristic) {
  int newMode = modeCharacteristic.value();
  // If mode changes, reset all integration and count variables.
  if (newMode != operationMode) {
    operationMode = newMode;
    resetSession();
    Serial.print("Mode updated to: ");
    Serial.println(operationMode);
    // For rotation mode, no calibration delay is needed.
    if (operationMode == 1) {
      calibrationDone = true;
    }
  }
}

void onSessionStatusWritten(BLEDevice central, BLECharacteristic characteristic) {
  sessionStatus = sessionStatusCharacteristic.value();
  Serial.print("Session status updated to: ");
  Serial.println(sessionStatus);
  if (sessionStatus == 1) {
    resetSession();
    // For rotation mode, no calibration delay; otherwise, wait 5 seconds.
    if (operationMode != 1) {
      calibrationDone = false;
      calibrationStartTime = millis();
    } else {
      calibrationDone = true;
    }
  }
}

void setup() {
  Serial.begin(115200);
  while (!Serial) ; 

  if (!IMU.begin()) {
    Serial.println("Failed to initialize IMU!");
    while (1) ;
  }
  if (!BLE.begin()) {
    Serial.println("BLE initialization failed!");
    while (1) ;
  }

  BLE.setLocalName("Gym_Arduino");
  BLE.setAdvertisedService(gymService);

  gymService.addCharacteristic(rotationTotalCharacteristic);
  gymService.addCharacteristic(repCountCharacteristic);
  gymService.addCharacteristic(distanceCountCharacteristic);
  gymService.addCharacteristic(stepCountCharacteristic);
  gymService.addCharacteristic(modeCharacteristic);
  gymService.addCharacteristic(sessionStatusCharacteristic);
  gymService.addCharacteristic(motionQualityCharacteristic);
  BLE.addService(gymService);

  // Write initial values to BLE characteristics
  rotationTotalCharacteristic.writeValue(cumulativeRotationDegrees);
  repCountCharacteristic.writeValue(repCount);
  distanceCountCharacteristic.writeValue(0);
  stepCountCharacteristic.writeValue(0);
  modeCharacteristic.writeValue(operationMode);
  sessionStatusCharacteristic.writeValue(sessionStatus);
  motionQualityCharacteristic.writeValue(motionQualityString);
  modeCharacteristic.setEventHandler(BLEWritten, onModeWritten);
  sessionStatusCharacteristic.setEventHandler(BLEWritten, onSessionStatusWritten);

  BLE.advertise();
  previousTimeMicros = micros();

  calibrateHorizontalAxis();
  calibrateVerticalAxis();

  Serial.println("IMU and BLE initialized successfully.");
}

void loop() {
  BLEDevice central = BLE.central();
  if (central) {
    Serial.print("Connected to Central: ");
    Serial.println(central.address());

    while (central.connected()) {
      // If session is inactive, do nothing.
      if (operationMode == 0 || sessionStatus == 0) {
        BLE.poll();
        delay(200);
        continue;
      }

      // Wait for calibration if needed (for modes 2, 3, and 4)
      if (sessionStatus == 1 && !calibrationDone) {
        if (millis() - calibrationStartTime >= CALIBRATION_DELAY_MS) {
          if (operationMode == 2) {
            calibrateVerticalAxis();
          } else if (operationMode == 3 || operationMode == 4) {
            calibrateHorizontalAxis();
          }
          calibrationDone = true;
          Serial.println("Calibration complete. Starting exercise.");
        } else {
          Serial.print("Calibrating... ");
          Serial.print((CALIBRATION_DELAY_MS - (millis() - calibrationStartTime)) / 1000);
          Serial.println(" seconds remaining");
          BLE.poll();
          delay(200);
          continue;  // Skip processing until calibration is complete
        }
      }

      //Mode 1: Rotation (Gyroscope)
      if (operationMode == 1 && sessionStatus == 1) {
        if (IMU.gyroscopeAvailable()) {
          float gx, gy, gz;
          if (IMU.readGyroscope(gx, gy, gz)) {
            unsigned long currentTime = micros();
            float dt = (currentTime - previousTimeMicros) / 1000000.0;
            previousTimeMicros = currentTime;

            float absGz = fabs(gz);
            if (absGz < gyroscopeNoiseThreshold)
              absGz = 0;
            float deltaDegrees = absGz * dt;
            cumulativeRotationDegrees += deltaDegrees;

            if (fabs(gz) >= gyroscopeNoiseThreshold) {
              int readingDirection = (gz > 0) ? 1 : -1;
              if (rotationDirection == 0) {
                rotationDirection = readingDirection;
                accumulatedAngleDegrees = deltaDegrees;
              } else if (readingDirection == rotationDirection) {
                accumulatedAngleDegrees += deltaDegrees;
              } else {
                if (accumulatedAngleDegrees >= rotationRepThresholdDegrees) {
                  repCount++;
                }
                rotationDirection = readingDirection;
                accumulatedAngleDegrees = deltaDegrees;
              }
            }

            rotationTotalCharacteristic.writeValue(cumulativeRotationDegrees);
            int displayedReps = repCount / 2;
            if (displayedReps != lastSentReps) {
              repCountCharacteristic.writeValue(displayedReps);
              lastSentReps = displayedReps;
            }
            Serial.print("Total rotation (degrees): ");
            Serial.println(cumulativeRotationDegrees);
            Serial.print("Reps: ");
            Serial.println(displayedReps);
          }
        }
      }

      // Mode 2: Vertical Pressing (Y-axis)
      if (operationMode == 2 && sessionStatus == 1) {
        if (IMU.accelerationAvailable()) {
          float ax, ay, az;
          if (IMU.readAcceleration(ax, ay, az)) {
            // Use the Y-axis for vertical pressing motion
            float rawAccel = ay;

            // Dynamic bias correction for vertical axis
            static float dynamicBias = baselineY;
            const float biasAlpha = 0.01;
            if (fabs(rawAccel - dynamicBias) < 0.3) {
              dynamicBias = (1 - biasAlpha) * dynamicBias + biasAlpha * rawAccel;
            }
            float calibratedAccel = rawAccel - dynamicBias;

            Serial.print("Raw accel (Y): ");
            Serial.println(rawAccel);
            Serial.print("Dynamic bias: ");
            Serial.println(dynamicBias);
            Serial.print("Calibrated accel (Y): ");
            Serial.println(calibratedAccel);

            if (fabs(calibratedAccel) < accelerationNoiseThreshold) {
              calibratedAccel = 0;
              verticalVelocity = 0;
            }

            unsigned long currentTime = micros();
            float dt = (currentTime - previousTimeMicros) / 1000000.0;
            previousTimeMicros = currentTime;

            float velocity = verticalVelocity + calibratedAccel * dt;
            float deltaDistance = verticalVelocity * dt + 0.5 * calibratedAccel * dt * dt;
            verticalVelocity = velocity;
            verticalTotalDistance += fabs(deltaDistance);

            // Peak-detection using time threshold
            static float currentDisp = 0;
            static float maxDisp = 0;
            static float minDisp = 0;
            static unsigned long lastMotionTime = millis();

            currentDisp += deltaDistance;
            if (fabs(calibratedAccel) >= accelerationNoiseThreshold) {
              lastMotionTime = millis();
              if (currentDisp > maxDisp) maxDisp = currentDisp;
              if (currentDisp < minDisp) minDisp = currentDisp;
            } else {
              if (millis() - lastMotionTime > INACTIVITY_MS) {
                if ((maxDisp - minDisp) >= pressingRepThresholdDistance) {
                  repCount++;
                }
                currentDisp = 0;
                maxDisp = 0;
                minDisp = 0;
              }
            }

            int displayedReps = repCount/2;
            if (displayedReps != lastSentReps) {
              repCountCharacteristic.writeValue(displayedReps);
              lastSentReps = displayedReps;
            }
            // Update distance (in centimeters)
            distanceCountCharacteristic.writeValue((int)(verticalTotalDistance * 100));

            Serial.print("Vertical Total Distance (cm): ");
            Serial.println(verticalTotalDistance * 100, 4);
            Serial.print("Reps: ");
            Serial.println(displayedReps);
          }
        }
      }

      // Mode 3: Horizontal Pressing (X-axis) 
      if (operationMode == 3 && sessionStatus == 1) {
        if (IMU.accelerationAvailable()) {
          float ax, ay, az;
          if (IMU.readAcceleration(ax, ay, az)) {
            // Use the X-axis for horizontal pressing motion
            float rawAccel = ax;

            // Dynamic bias correction for horizontal axis
            static float dynamicBias = baselineX;
            const float biasAlpha = 0.01;
            if (fabs(rawAccel - dynamicBias) < 0.3) {
              dynamicBias = (1 - biasAlpha) * dynamicBias + biasAlpha * rawAccel;
            }
            float calibratedAccel = rawAccel - dynamicBias;

            Serial.print("Raw accel (X): ");
            Serial.println(rawAccel);
            Serial.print("Dynamic bias: ");
            Serial.println(dynamicBias);
            Serial.print("Calibrated accel (X): ");
            Serial.println(calibratedAccel);

            if (fabs(calibratedAccel) < accelerationNoiseThreshold) {
              calibratedAccel = 0;
              horizontalVelocity = 0;
            }

            unsigned long currentTime = micros();
            float dt = (currentTime - previousTimeMicros) / 1000000.0;
            previousTimeMicros = currentTime;

            float velocity = horizontalVelocity + calibratedAccel * dt;
            float deltaDistance = horizontalVelocity * dt + 0.5 * calibratedAccel * dt * dt;
            horizontalVelocity = velocity;
            horizontalTotalDistance += fabs(deltaDistance);

            // Peak-detection using time threshold
            static float currentDisp = 0;
            static float maxDisp = 0;
            static float minDisp = 0;
            static unsigned long lastMotionTime = millis();

            currentDisp += deltaDistance;
            if (fabs(calibratedAccel) >= accelerationNoiseThreshold) {
              lastMotionTime = millis();
              if (currentDisp > maxDisp) maxDisp = currentDisp;
              if (currentDisp < minDisp) minDisp = currentDisp;
            } else {
              if (millis() - lastMotionTime > INACTIVITY_MS) {
                if ((maxDisp - minDisp) >= pressingRepThresholdDistance) {
                  repCount++;
                }
                currentDisp = 0;
                maxDisp = 0;
                minDisp = 0;
              }
            }

            int displayedReps = repCount/2;
            if (displayedReps != lastSentReps) {
              repCountCharacteristic.writeValue(displayedReps);
              lastSentReps = displayedReps;
            }
            distanceCountCharacteristic.writeValue((int)(horizontalTotalDistance * 100));

            Serial.print("Horizontal Total Distance (cm): ");
            Serial.println(horizontalTotalDistance * 100, 4);
            Serial.print("Reps: ");
            Serial.println(displayedReps);
          }
        }
      }

      // Mode 4: Step Counter 
      if (operationMode == 4 && sessionStatus == 1) {
        if (IMU.accelerationAvailable()) {
          float ax, ay, az;
          if (IMU.readAcceleration(ax, ay, az)) {
            // Calculate the magnitude of the acceleration vector.
            float mag = sqrt(ax * ax + ay * ay + az * az);
            // Subtract gravity (assuming 9.81 m/s²) to get the dynamic component.
            float dynAccel = fabs(mag - 9.81);

            // Simple step detection: when dynamic acceleration exceeds a threshold.
            static bool stepDetected = false;
            static unsigned long lastStepTime = 0;
            const float stepThreshold = 1.0;   // Adjust this threshold as needed.
            const float stepThresholdLow = 0.5;  // Lower threshold to reset detection.
            const unsigned long stepMinInterval = 300;  // Minimum 300 ms between steps.

            if (dynAccel > stepThreshold && !stepDetected && (millis() - lastStepTime > stepMinInterval)) {
              stepCount++;
              lastStepTime = millis();
              stepDetected = true;
            }
            if (dynAccel < stepThresholdLow) {
              stepDetected = false;
            }

            // Update the step count BLE characteristic.
            stepCountCharacteristic.writeValue(stepCount);
            Serial.print("Steps: ");
            Serial.println(stepCount);
          }
        }
      }

      BLE.poll();
      delay(50);
    }
    Serial.print("Disconnected from central: ");
    Serial.println(central.address());
  }
}