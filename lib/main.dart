import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:math'; // For mocking data
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

const String googleMapsApiKey = 'API_KEY';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Rider Map View',
      debugShowCheckedModeBanner: false,
      home: JobRouteScreen(),
    );
  }
}

class JobRouteScreen extends StatefulWidget {
  const JobRouteScreen({super.key});

  @override
  State<JobRouteScreen> createState() => _JobRouteScreenState();
}

class _JobRouteScreenState extends State<JobRouteScreen> {
  GoogleMapController? mapController;
  LatLng? _riderLocation;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  String _totalDistance = "Calculating...";
  String _totalDuration = "Calculating...";
  final List<Map<String, dynamic>> originalPickups = [
    {
      "id": 1,
      "location": LatLng(12.983212, 77.610411),
      "time_slot": "9AM-10AM",
      "inventory": 4
    },
    {
      "id": 2,
      "location": LatLng(12.943109, 77.593765),
      "time_slot": "9AM-10AM",
      "inventory": 6
    },
    {
      "id": 3,
      "location": LatLng(12.966852, 77.623481),
      "time_slot": "10AM-11AM",
      "inventory": 3
    },
    {
      "id": 4,
      "location": LatLng(12.951105, 77.580123),
      "time_slot": "10AM-11AM",
      "inventory": 8
    },
    {
      "id": 5,
      "location": LatLng(12.978631, 77.589342),
      "time_slot": "11AM-12PM",
      "inventory": 5
    }
  ];

  final LatLng warehouseLocation = const LatLng(12.961115, 77.600000);

  List<Map<String, dynamic>> _mockedPickups = [];

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
  }

  Future<void> _requestLocationPermission() async {
    if (kIsWeb) {
      _getCurrentLocation();
    } else {
      PermissionStatus status = await Permission.locationWhenInUse.request();
      if (status.isGranted) {
        _getCurrentLocation();
      } else if (status.isDenied) {
        _showPermissionDeniedDialog();
      } else if (status.isPermanentlyDenied) {
        _showPermissionDeniedDialog(permanentlyDenied: true);
      }
    }
  }

  void _showPermissionDeniedDialog({bool permanentlyDenied = false}) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Location Permission Denied"),
          content: Text(
            permanentlyDenied
                ? "Location permission is permanently denied. Please enable it from app settings to use this feature."
                : "Please grant location permission to use this feature.",
          ),
          actions: <Widget>[
            TextButton(
              child: const Text("OK"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            if (permanentlyDenied)
              TextButton(
                child: const Text("Open Settings"),
                onPressed: () {
                  openAppSettings();
                  Navigator.of(context).pop();
                },
              ),
          ],
        );
      },
    );
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _riderLocation = LatLng(position.latitude, position.longitude);
        _addRiderMarker();
        _mockPickupLocations();
        _addLocationMarkers();
        _drawRoute();
      });

      if (mapController != null && _riderLocation != null) {
        mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            _riderLocation!,
            14.0,
          ),
        );
      }
    } catch (e) {
      print("Error getting current location: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error getting your current location: $e")),
      );
    }
  }

  void _mockPickupLocations() {
    if (_riderLocation == null) return;

    const double radiusKm = 5.0;
    const double earthRadiusKm = 6371.0;

    _mockedPickups = [];
    final Random random = Random();

    for (int i = 0; i < originalPickups.length; i++) {
      double angle = 2 * pi * random.nextDouble();
      double distance = radiusKm * sqrt(random.nextDouble());

      double deltaLat = (distance * sin(angle)) / earthRadiusKm * (180 / pi);
      double deltaLon = (distance * cos(angle)) /
          earthRadiusKm *
          (180 / pi) /
          cos(_riderLocation!.latitude * pi / 180);

      double newLat = _riderLocation!.latitude + deltaLat;
      double newLon = _riderLocation!.longitude + deltaLon;

      _mockedPickups.add({
        "id": originalPickups[i]["id"],
        "location": LatLng(newLat, newLon),
        "time_slot": originalPickups[i]["time_slot"],
        "inventory": originalPickups[i]["inventory"],
      });
    }
  }

  void _addRiderMarker() {
    if (_riderLocation != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId("riderLocation"),
          position: _riderLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueBlue,
          ), // Blue marker for rider
          infoWindow: const InfoWindow(title: "Your Location"),
        ),
      );
    }
  }

  void _addLocationMarkers() {
    _markers.add(
      Marker(
        markerId: const MarkerId("warehouseLocation"),
        position: warehouseLocation,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueGreen,
        ),
        infoWindow: const InfoWindow(title: "Warehouse"),
      ),
    );

    for (int i = 0; i < _mockedPickups.length; i++) {
      final pickup = _mockedPickups[i];
      _markers.add(
        Marker(
          markerId: MarkerId("pickup${pickup['id']}"),
          position: pickup['location'],
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
          infoWindow: InfoWindow(
            title: "Pickup ${pickup['id']}",
            snippet:
                "Slot: ${pickup['time_slot']}, Inventory: ${pickup['inventory']}",
          ),
        ),
      );
    }
    setState(
      () {},
    );
  }

  Future<void> _drawRoute() async {
    if (_riderLocation == null || _mockedPickups.isEmpty) {
      print(
        "Cannot draw route: Rider location or mocked pickups not available.",
      );
      return;
    }

    _polylines.clear();

    final String origin =
        "${_riderLocation!.latitude},${_riderLocation!.longitude}";

    final String destination =
        "${_mockedPickups.last['location'].latitude},${_mockedPickups.last['location'].longitude}";

    String waypoints = '';
    if (_mockedPickups.length > 1) {
      waypoints = _mockedPickups
          .sublist(0, _mockedPickups.length - 1)
          .map(
            (pickup) =>
                "${pickup['location'].latitude},${pickup['location'].longitude}",
          )
          .join('|');
    }

    // Construct the full URL for the Google Directions API request
    final String url = waypoints.isNotEmpty
        ? "https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&waypoints=$waypoints&key=$googleMapsApiKey"
        : "https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&key=$googleMapsApiKey";

    print("Directions API URL: $url");

    try {
      final response = await http.get(
        Uri.parse(url),
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(
          response.body,
        );

        print("Directions API Response Body: ${response.body}");

        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final String encodedPolyline =
              data['routes'][0]['overview_polyline']['points'];
          final List<PointLatLng> decodedPoints =
              PolylinePoints().decodePolyline(encodedPolyline);

          List<LatLng> polylineCoordinates = decodedPoints
              .map((point) => LatLng(point.latitude, point.longitude))
              .toList();

          setState(() {
            _polylines.add(
              Polyline(
                polylineId: const PolylineId(
                  "fullRoute",
                ),
                points: polylineCoordinates,
                color: Colors.blue,
                width: 5,
              ),
            );

            double totalDistanceValue = 0;
            int totalDurationValue = 0;

            if (data['routes'][0]['legs'] != null) {
              for (var leg in data['routes'][0]['legs']) {
                if (leg['distance'] != null &&
                    leg['distance']['value'] != null) {
                  totalDistanceValue +=
                      (leg['distance']['value'] as num).toDouble();
                }
                if (leg['duration'] != null &&
                    leg['duration']['value'] != null) {
                  totalDurationValue +=
                      (leg['duration']['value'] as num).toInt();
                }
              }
            }

            print(
                "Calculated Total Distance Value (meters): $totalDistanceValue");
            print(
                "Calculated Total Duration Value (seconds): $totalDurationValue");
            _totalDistance =
                (totalDistanceValue / 1000).toStringAsFixed(2) + ' km';
            int hours = totalDurationValue ~/ 3600;
            int minutes = (totalDurationValue % 3600) ~/ 60;
            _totalDuration = '${hours}h ${minutes}m';

            print("Updated _totalDistance: $_totalDistance");
            print("Updated _totalDuration: $_totalDuration");
          });
        } else {
          print("No routes found by Directions API. Status: ${data['status']}");
          setState(() {
            _totalDistance = "N/A";
            _totalDuration = "N/A";
          });
        }
      } else {
        print("Failed to load directions. Status Code: ${response.statusCode}");
        print("Response body: ${response.body}");
        setState(() {
          _totalDistance = "Error";
          _totalDuration = "Error";
        });
      }
    } catch (e) {
      print("Error fetching directions in catch block: $e");
      setState(() {
        _totalDistance = "Error";
        _totalDuration = "Error";
      });
    }
  }

  Future<void> _launchGoogleMapsNavigation() async {
    if (_riderLocation == null || _mockedPickups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait for location and route to load.'),
        ),
      );
      return;
    }

    final String originParam =
        "${_riderLocation!.latitude},${_riderLocation!.longitude}";

    final String destinationParam =
        "${_mockedPickups.last['location'].latitude},${_mockedPickups.last['location'].longitude}";

    String waypointsParam = '';
    if (_mockedPickups.length > 1) {
      waypointsParam = _mockedPickups
          .sublist(0, _mockedPickups.length - 1)
          .map(
            (pickup) =>
                "${pickup['location'].latitude},${pickup['location'].longitude}",
          )
          .join('|');
    }

    final String googleMapsUrl = waypointsParam.isNotEmpty
        ? "http://maps.google.com/maps?saddr=$originParam&daddr=$destinationParam&waypoints=$waypointsParam&dirflg=d"
        : "http://maps.google.com/maps?saddr=$originParam&daddr=$destinationParam&dirflg=d";

    final Uri url = Uri.parse(
      googleMapsUrl,
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      print('Could not launch Google Maps URL: $url');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open Google Maps. Make sure the app is installed.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rider Job Route'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _riderLocation == null
          ? const Center(
              child: CircularProgressIndicator(color: Colors.deepPurple),
            )
          : Stack(
              children: [
                GoogleMap(
                  onMapCreated: (controller) {
                    mapController = controller;
                    if (_riderLocation != null) {
                      mapController!.animateCamera(
                        CameraUpdate.newLatLngZoom(_riderLocation!, 14.0),
                      );
                    }
                  },
                  initialCameraPosition: CameraPosition(
                    target: _riderLocation!,
                    zoom: 14.0,
                  ),
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: false,
                ),
                Positioned(
                  bottom: 16.0,
                  left: 16.0,
                  right: 16.0,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12.0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(
                            10.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(
                                0.2,
                              ),
                              blurRadius: 8,
                              offset: const Offset(
                                0,
                                4,
                              ),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                const Text(
                                  "Total Distance",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                                Text(
                                  _totalDistance,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              children: [
                                const Text(
                                  "Estimated Time",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                                Text(
                                  _totalDuration,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(
                        height: 15,
                      ),
                      ElevatedButton(
                        onPressed: _launchGoogleMapsNavigation,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(
                            double.infinity,
                            55,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              10,
                            ),
                          ),
                          elevation: 5,
                        ),
                        child: const Text(
                          'Navigate',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
