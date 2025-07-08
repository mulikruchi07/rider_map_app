# Job Route Screen - Flutter App

This Flutter application displays a Google Map with the rider’s current location, multiple pickup locations, a warehouse location, and a polyline route connecting all points in order.

## Features

- Displays rider’s live location using device GPS
- Shows markers for:
  - Rider
  - Five pickup locations (within 5 km radius)
  - Warehouse location
- Draws polyline route:
  - Starts at rider location
  - Passes through all pickup points in sequence
  - Ends at the warehouse
- Uses Google Directions API to render actual road routes
- Location permission handling integrated

## How to Run

1. Extract the zip file or clone the repository.

2. Run `flutter pub get` to install dependencies.

3. Replace the API key placeholder in `main.dart`:
   ```dart
   final String googleApiKey = 'API_KEY';
