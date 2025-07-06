import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;

void main() {
  runApp(
    const ProviderScope(
      child: WeatherApp(),
    ),
  );
}

class WeatherApp extends StatelessWidget {
  const WeatherApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Weather App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
      ),
      home: const WeatherScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Weather Data Models
class WeatherData {
  final String location;
  final String country;
  final double temperature;
  final String condition;
  final String description;
  final int humidity;
  final double windSpeed;
  final double feelsLike;
  final int pressure;
  final int visibility;
  final List<HourlyForecast> hourlyForecast;
  final List<DailyForecast> dailyForecast;
  final DateTime sunrise;
  final DateTime sunset;

  WeatherData({
    required this.location,
    required this.country,
    required this.temperature,
    required this.condition,
    required this.description,
    required this.humidity,
    required this.windSpeed,
    required this.feelsLike,
    required this.pressure,
    required this.visibility,
    required this.hourlyForecast,
    required this.dailyForecast,
    required this.sunrise,
    required this.sunset,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json, List<dynamic> forecast) {
    final current = json['current'];
    final location = json['location'];

    // Parse hourly forecast (next 5 hours)
    List<HourlyForecast> hourlyList = [];
    if (forecast.isNotEmpty) {
      final today = forecast[0]['hour'] as List;
      final currentHour = DateTime.now().hour;

      for (int i = 0; i < 5; i++) {
        final hourIndex = (currentHour + i + 1) % 24;
        if (hourIndex < today.length) {
          final hourData = today[hourIndex];
          hourlyList.add(HourlyForecast(
            time: _formatHour(hourIndex),
            temperature: hourData['temp_c']?.toDouble() ?? 0.0,
            condition: hourData['condition']['text'] ?? '',
          ));
        }
      }
    }

    // Parse daily forecast
    List<DailyForecast> dailyList = [];
    for (int i = 0; i < math.min(5, forecast.length); i++) {
      final day = forecast[i];
      final dayData = day['day'];
      dailyList.add(DailyForecast(
        day: i == 0 ? 'Today' : _formatDay(DateTime.parse(day['date'])),
        highTemp: dayData['maxtemp_c']?.toDouble() ?? 0.0,
        lowTemp: dayData['mintemp_c']?.toDouble() ?? 0.0,
        condition: dayData['condition']['text'] ?? '',
      ));
    }

    return WeatherData(
      location: location['name'] ?? '',
      country: location['country'] ?? '',
      temperature: current['temp_c']?.toDouble() ?? 0.0,
      condition: current['condition']['text'] ?? '',
      description: current['condition']['text'] ?? '',
      humidity: current['humidity']?.toInt() ?? 0,
      windSpeed: current['wind_kph']?.toDouble() ?? 0.0,
      feelsLike: current['feelslike_c']?.toDouble() ?? 0.0,
      pressure: current['pressure_mb']?.toInt() ?? 0,
      visibility: current['vis_km']?.toInt() ?? 0,
      hourlyForecast: hourlyList,
      dailyForecast: dailyList,
      sunrise: DateTime.parse("${DateTime.now().toString().split('T')[0]}T06:00:00"),
      sunset: DateTime.parse("${DateTime.now().toString().split('T')[0]}T18:00:00"),
    );
  }

  static String _formatHour(int hour) {
    if (hour == 0) return '12 AM';
    if (hour < 12) return '$hour AM';
    if (hour == 12) return '12 PM';
    return '${hour - 12} PM';
  }

  static String _formatDay(DateTime date) {
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[date.weekday - 1];
  }
}

class HourlyForecast {
  final String time;
  final double temperature;
  final String condition;

  HourlyForecast({
    required this.time,
    required this.temperature,
    required this.condition,
  });
}

class DailyForecast {
  final String day;
  final double highTemp;
  final double lowTemp;
  final String condition;

  DailyForecast({
    required this.day,
    required this.highTemp,
    required this.lowTemp,
    required this.condition,
  });
}

class LocationData {
  final double latitude;
  final double longitude;
  final String city;
  final String country;

  LocationData({
    required this.latitude,
    required this.longitude,
    required this.city,
    required this.country,
  });
}

// Services
class LocationService {
  static Future<LocationData> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Check if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    // Check location permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied, we cannot request permissions.');
    }

    // Get current position
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    // Get city name from coordinates
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        return LocationData(
          latitude: position.latitude,
          longitude: position.longitude,
          city: place.locality ?? place.administrativeArea ?? 'Unknown',
          country: place.country ?? 'Unknown',
        );
      }
    } catch (e) {
      // If geocoding fails, still return coordinates
    }

    return LocationData(
      latitude: position.latitude,
      longitude: position.longitude,
      city: 'Unknown Location',
      country: 'Unknown',
    );
  }
}

class WeatherService {
  // Replace with your actual WeatherAPI key from https://www.weatherapi.com/
  static const String _apiKey = 'f61e6128ead548c99de220942252006';
  static const String _baseUrl = 'http://api.weatherapi.com/v1';

  static Future<WeatherData> getWeatherByLocation(LocationData location) async {
    try {
      final url = '$_baseUrl/forecast.json?key=$_apiKey&q=${location.latitude},${location.longitude}&days=5&aqi=no&alerts=no';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return WeatherData.fromJson(jsonData, jsonData['forecast']['forecastday']);
      } else {
        throw Exception('Failed to load weather data: ${response.statusCode}');
      }
    } catch (e) {
      // Fallback to mock data if API fails
      return _getMockWeatherData(location);
    }
  }

  static WeatherData _getMockWeatherData(LocationData location) {
    // Mock data as fallback
    final random = math.Random();
    final conditions = ['Sunny', 'Partly Cloudy', 'Cloudy', 'Light Rain'];
    final condition = conditions[random.nextInt(conditions.length)];

    return WeatherData(
      location: location.city,
      country: location.country,
      temperature: 20.0 + random.nextDouble() * 15,
      condition: condition,
      description: condition,
      humidity: 50 + random.nextInt(40),
      windSpeed: 5.0 + random.nextDouble() * 15,
      feelsLike: 18.0 + random.nextDouble() * 20,
      pressure: 1000 + random.nextInt(50),
      visibility: 8 + random.nextInt(7),
      hourlyForecast: List.generate(5, (index) {
        final hour = DateTime.now().hour + index + 1;
        return HourlyForecast(
          time: WeatherData._formatHour(hour % 24),
          temperature: 18.0 + random.nextDouble() * 12,
          condition: conditions[random.nextInt(conditions.length)],
        );
      }),
      dailyForecast: List.generate(5, (index) {
        return DailyForecast(
          day: index == 0 ? 'Today' : WeatherData._formatDay(
              DateTime.now().add(Duration(days: index))
          ),
          highTemp: 20.0 + random.nextDouble() * 15,
          lowTemp: 10.0 + random.nextDouble() * 10,
          condition: conditions[random.nextInt(conditions.length)],
        );
      }),
      sunrise: DateTime.now().copyWith(hour: 6, minute: 30),
      sunset: DateTime.now().copyWith(hour: 18, minute: 45),
    );
  }
}

// Providers
final locationProvider = FutureProvider<LocationData>((ref) async {
  return await LocationService.getCurrentLocation();
});

final weatherProvider = StateNotifierProvider<WeatherNotifier, AsyncValue<WeatherData>>((ref) {
  return WeatherNotifier(ref);
});

class WeatherNotifier extends StateNotifier<AsyncValue<WeatherData>> {
  final Ref ref;

  WeatherNotifier(this.ref) : super(const AsyncValue.loading()) {
    loadWeatherData();
  }

  Future<void> loadWeatherData() async {
    try {
      state = const AsyncValue.loading();

      // Get current location
      final location = await ref.read(locationProvider.future);

      // Get weather data for current location
      final weatherData = await WeatherService.getWeatherByLocation(location);

      state = AsyncValue.data(weatherData);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> refreshWeather() async {
    // Invalidate location provider to get fresh location
    ref.invalidate(locationProvider);
    await loadWeatherData();
  }
}

// Permission Status Provider
final permissionStatusProvider = StateNotifierProvider<PermissionStatusNotifier, PermissionStatus>((ref) {
  return PermissionStatusNotifier();
});

enum PermissionStatus { unknown, granted, denied, deniedForever, serviceDisabled }

class PermissionStatusNotifier extends StateNotifier<PermissionStatus> {
  PermissionStatusNotifier() : super(PermissionStatus.unknown);

  Future<void> requestPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        state = PermissionStatus.serviceDisabled;
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      switch (permission) {
        case LocationPermission.denied:
          state = PermissionStatus.denied;
          break;
        case LocationPermission.deniedForever:
          state = PermissionStatus.deniedForever;
          break;
        case LocationPermission.whileInUse:
        case LocationPermission.always:
          state = PermissionStatus.granted;
          break;
        default:
          state = PermissionStatus.unknown;
      }
    } catch (e) {
      state = PermissionStatus.denied;
    }
  }

  void openSettings() {
    Geolocator.openAppSettings();
  }

  void openLocationSettings() {
    Geolocator.openLocationSettings();
  }
}

// Main Weather Screen
class WeatherScreen extends ConsumerStatefulWidget {
  const WeatherScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends ConsumerState<WeatherScreen> {
  @override
  void initState() {
    super.initState();
    // Request location permission on app start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(permissionStatusProvider.notifier).requestPermission();
    });
  }

  @override
  Widget build(BuildContext context) {
    final weatherAsync = ref.watch(weatherProvider);
    final permissionStatus = ref.watch(permissionStatusProvider);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: _getGradientForWeather(weatherAsync.value?.condition ?? 'Sunny'),
        ),
        child: SafeArea(
          child: _buildContent(weatherAsync, permissionStatus),
        ),
      ),
    );
  }

  Widget _buildContent(AsyncValue<WeatherData> weatherAsync, PermissionStatus permissionStatus) {
    // Handle permission states
    if (permissionStatus == PermissionStatus.denied ||
        permissionStatus == PermissionStatus.deniedForever ||
        permissionStatus == PermissionStatus.serviceDisabled) {
      return PermissionDeniedWidget(
        permissionStatus: permissionStatus,
        onRetry: () => ref.read(permissionStatusProvider.notifier).requestPermission(),
        onOpenSettings: () => ref.read(permissionStatusProvider.notifier).openSettings(),
        onOpenLocationSettings: () => ref.read(permissionStatusProvider.notifier).openLocationSettings(),
      );
    }

    return weatherAsync.when(
      loading: () => const LoadingWidget(),
      error: (error, stack) => ErrorWidget(
        error: error.toString(),
        onRetry: () => ref.read(weatherProvider.notifier).refreshWeather(),
      ),
      data: (weather) => WeatherContent(weather: weather),
    );
  }

  LinearGradient _getGradientForWeather(String condition) {
    switch (condition.toLowerCase()) {
      case 'sunny':
      case 'clear':
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFB347), Color(0xFFFFCC33), Color(0xFFFFD700)],
        );
      case 'cloudy':
      case 'overcast':
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF78909C), Color(0xFF90A4AE), Color(0xFFB0BEC5)],
        );
      case 'rainy':
      case 'rain':
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF37474F), Color(0xFF546E7A), Color(0xFF78909C)],
        );
      case 'partly cloudy':
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF4A90E2), Color(0xFF50A3F7), Color(0xFF7BB3F7)],
        );
      default:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF4A90E2), Color(0xFF50A3F7), Color(0xFF7BB3F7)],
        );
    }
  }
}

// Permission Denied Widget
class PermissionDeniedWidget extends StatelessWidget {
  final PermissionStatus permissionStatus;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenLocationSettings;

  const PermissionDeniedWidget({
    Key? key,
    required this.permissionStatus,
    required this.onRetry,
    required this.onOpenSettings,
    required this.onOpenLocationSettings,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    String title;
    String message;
    String buttonText;
    VoidCallback buttonAction;

    switch (permissionStatus) {
      case PermissionStatus.serviceDisabled:
        title = 'Location Services Disabled';
        message = 'Please enable location services to get weather for your current location.';
        buttonText = 'Open Location Settings';
        buttonAction = onOpenLocationSettings;
        break;
      case PermissionStatus.deniedForever:
        title = 'Location Permission Required';
        message = 'Location access is permanently denied. Please enable it in app settings to get weather for your current location.';
        buttonText = 'Open App Settings';
        buttonAction = onOpenSettings;
        break;
      default:
        title = 'Location Permission Required';
        message = 'We need location access to provide weather information for your current location.';
        buttonText = 'Grant Permission';
        buttonAction = onRetry;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.location_off,
              size: 80,
              color: Colors.white70,
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 16,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: buttonAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }
}

// Loading Widget with Animation
class LoadingWidget extends StatefulWidget {
  const LoadingWidget({Key? key}) : super(key: key);

  @override
  State<LoadingWidget> createState() => _LoadingWidgetState();
}

class _LoadingWidgetState extends State<LoadingWidget>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: 0, end: 2 * math.pi).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Transform.rotate(
                angle: _animation.value,
                child: const Icon(
                  Icons.wb_sunny,
                  size: 60,
                  color: Colors.white,
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          const Text(
            'Getting your location...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Loading weather data...',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// Error Widget
class ErrorWidget extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const ErrorWidget({
    Key? key,
    required this.error,
    required this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 60,
              color: Colors.white70,
            ),
            const SizedBox(height: 20),
            const Text(
              'Unable to load weather data',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              error.contains('Location')
                  ? 'Please check your location settings'
                  : 'Please check your internet connection',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

// Main Weather Content
class WeatherContent extends StatefulWidget {
  final WeatherData weather;

  const WeatherContent({Key? key, required this.weather}) : super(key: key);

  @override
  State<WeatherContent> createState() => _WeatherContentState();
}

class _WeatherContentState extends State<WeatherContent>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    ));

    // Start animations
    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        final ref = ProviderScope.containerOf(context).read(weatherProvider.notifier);
        await ref.refreshWeather();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: WeatherHeader(weather: widget.weather),
                ),
              ),

              const SizedBox(height: 30),

              // Current Weather Card
              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: CurrentWeatherCard(weather: widget.weather),
                ),
              ),

              const SizedBox(height: 20),

              // Weather Details
              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: WeatherDetailsCard(weather: widget.weather),
                ),
              ),

              const SizedBox(height: 20),

              // Hourly Forecast
              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: HourlyForecastCard(forecasts: widget.weather.hourlyForecast),
                ),
              ),

              const SizedBox(height: 20),

              // Daily Forecast
              FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: DailyForecastCard(forecasts: widget.weather.dailyForecast),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Weather Header
class WeatherHeader extends StatelessWidget {
  final WeatherData weather;

  const WeatherHeader({Key? key, required this.weather}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                weather.location,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                weather.country,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Today, ${DateTime.now().day}/${DateTime.now().month}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
        Column(
          children: [
            IconButton(
              onPressed: () {
                final ref = ProviderScope.containerOf(context).read(weatherProvider.notifier);
                ref.refreshWeather();
              },
              icon: const Icon(
                Icons.refresh,
                color: Colors.white,
              ),
              tooltip: 'Refresh',
            ),
            Icon(
              Icons.location_on,
              color: Colors.white.withOpacity(0.7),
              size: 16,
            ),
          ],
        ),
      ],
    );
  }
}

// Current Weather Card
class CurrentWeatherCard extends StatefulWidget {
  final WeatherData weather;

  const CurrentWeatherCard({Key? key, required this.weather}) : super(key: key);

  @override
  State<CurrentWeatherCard> createState() => _CurrentWeatherCardState();
}

class _CurrentWeatherCardState extends State<CurrentWeatherCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Icon(
                  _getWeatherIcon(widget.weather.condition),
                  size: 100,
                  color: Colors.white,
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            '${widget.weather.temperature.round()}°',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 72,
              fontWeight: FontWeight.w200,
            ),
          ),
          Text(
            widget.weather.condition,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 20,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Feels like ${widget.weather.feelsLike.round()}°',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getWeatherIcon(String condition) {
    switch (condition.toLowerCase()) {
      case 'sunny':
      case 'clear':
        return Icons.wb_sunny;
      case 'cloudy':
      case 'overcast':
        return Icons.cloud;
      case 'partly cloudy':
        return Icons.wb_cloudy;
      case 'rainy':
      case 'rain':
      case 'light rain':
        return Icons.grain;
      case 'snow':
        return Icons.ac_unit;
      default:
        return Icons.wb_sunny;
    }
  }
}

// Weather Details Card
class WeatherDetailsCard extends StatelessWidget {
  final WeatherData weather;

  const WeatherDetailsCard({Key? key, required this.weather}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildDetailItem(
                Icons.water_drop,
                'Humidity',
                '${weather.humidity}%',
              ),
              _buildDetailItem(
                Icons.air,
                'Wind',
                '${weather.windSpeed.round()} km/h',
              ),
              _buildDetailItem(
                Icons.visibility,
                'Visibility',
                '${weather.visibility} km',
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildDetailItem(
                Icons.thermostat,
                'Pressure',
                '${weather.pressure} mb',
              ),
              _buildDetailItem(
                Icons.wb_sunny_outlined,
                'Sunrise',
                '${weather.sunrise.hour}:${weather.sunrise.minute.toString().padLeft(2, '0')}',
              ),
              _buildDetailItem(
                Icons.wb_twilight,
                'Sunset',
                '${weather.sunset.hour}:${weather.sunset.minute.toString().padLeft(2, '0')}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(
          icon,
          color: Colors.white.withOpacity(0.7),
          size: 24,
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// Hourly Forecast Card
class HourlyForecastCard extends StatelessWidget {
  final List<HourlyForecast> forecasts;

  const HourlyForecastCard({Key? key, required this.forecasts}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hourly Forecast',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            height: 120,
            child: forecasts.isEmpty
                ? Center(
              child: Text(
                'No hourly data available',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                ),
              ),
            )
                : ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: forecasts.length,
              itemBuilder: (context, index) {
                return _buildHourlyItem(forecasts[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHourlyItem(HourlyForecast forecast) {
    return Container(
      width: 80,
      margin: const EdgeInsets.only(right: 15),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            forecast.time,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Icon(
            _getWeatherIcon(forecast.condition),
            color: Colors.white,
            size: 24,
          ),
          const SizedBox(height: 8),
          Text(
            '${forecast.temperature.round()}°',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getWeatherIcon(String condition) {
    switch (condition.toLowerCase()) {
      case 'sunny':
      case 'clear':
        return Icons.wb_sunny;
      case 'cloudy':
      case 'overcast':
        return Icons.cloud;
      case 'partly cloudy':
        return Icons.wb_cloudy;
      case 'rainy':
      case 'rain':
      case 'light rain':
        return Icons.grain;
      case 'snow':
        return Icons.ac_unit;
      default:
        return Icons.wb_sunny;
    }
  }
}

// Daily Forecast Card
class DailyForecastCard extends StatelessWidget {
  final List<DailyForecast> forecasts;

  const DailyForecastCard({Key? key, required this.forecasts}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '5-Day Forecast',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 15),
          ...forecasts.map((forecast) => _buildDailyItem(forecast)).toList(),
        ],
      ),
    );
  }

  Widget _buildDailyItem(DailyForecast forecast) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              forecast.day,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 16,
              ),
            ),
          ),
          Expanded(
            child: Icon(
              _getWeatherIcon(forecast.condition),
              color: Colors.white,
              size: 20,
            ),
          ),
          Expanded(
            child: Text(
              '${forecast.highTemp.round()}°',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${forecast.lowTemp.round()}°',
              textAlign: TextAlign.end,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getWeatherIcon(String condition) {
    switch (condition.toLowerCase()) {
      case 'sunny':
      case 'clear':
        return Icons.wb_sunny;
      case 'cloudy':
      case 'overcast':
        return Icons.cloud;
      case 'partly cloudy':
        return Icons.wb_cloudy;
      case 'rainy':
      case 'rain':
      case 'light rain':
        return Icons.grain;
      case 'snow':
        return Icons.ac_unit;
      default:
        return Icons.wb_sunny;
    }
  }
}