import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// -----------------------------------------------------
/// SMART FILTER + FIREBASE + FASTAPI COMMUNICATION
/// -----------------------------------------------------
/// This code demonstrates how to:
///  1) Fetch data from a Firebase collection ("dishes").
///  2) Perform a 'smart filter' on that data based on user query attributes.
///  3) Send the user query to a FastAPI backend, receive structured parameters,
///     and then apply them to filter the Firebase data.
///  4) Display the resulting list of dishes with a dynamic UI in Flutter.
/// -----------------------------------------------------

/// Smart filter: fetch all dishes, score them based on query attributes,
/// and return the best matching dishes. Accepts a dynamic query map
/// (from FastAPI) instead of hard-coded values.
Future<List<Map<String, dynamic>>> getBestMatchingDishes(
  Map<String, dynamic> query,
) async {
  print("Inside getBestMatchingDishes with query: $query");

  // Reference to Firestore
  final db = FirebaseFirestore.instance;

  // Only consider non-null attributes for filtering
  final nonNullKeys = query.entries.where((e) => e.value != null).toList();

  // Fetch all dishes from the "dishes" collection in Firestore
  final snapshot = await db.collection("dishes").get();
  final allDishes =
      snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();

  // We'll store dishes that have a non-zero match_score here
  List<Map<String, dynamic>> scoredDishes = [];

  // Evaluate each dish
  for (var dish in allDishes) {
    // If the user has a dietary restriction that exactly matches the dish,
    // skip this dish (exclude it from the results).
    if (query.containsKey("dietary_restrictions") &&
        query["dietary_restrictions"] is String &&
        dish["dietary_restrictions"] is String) {
      if (dish["dietary_restrictions"].toString().toLowerCase() ==
          query["dietary_restrictions"].toString().toLowerCase()) {
        continue; // Skip this dish entirely.
      }
    }

    // We'll increment 'score' for each matching attribute
    int score = 0;

    for (var entry in nonNullKeys) {
      String key = entry.key;
      dynamic queryValue = entry.value;
      dynamic dishValue = dish[key];

      // Special handling if both the query and the dish have 'dietary_restrictions' as lists
      if (key == 'dietary_restrictions' &&
          queryValue is List &&
          dishValue is List) {
        // If there's any overlap between the user's dietary restrictions and the dish's
        if (queryValue.any((element) => dishValue.contains(element))) {
          score += 1;
        }
      }
      // Otherwise, compare values as strings
      else if (dishValue != null &&
          dishValue.toString().toLowerCase() ==
              queryValue.toString().toLowerCase()) {
        score += 1;
      }
    }

    // If the dish has a positive match_score, store it
    if (score > 0) {
      dish["match_score"] = score;
      scoredDishes.add(dish);
    }
  }

  // If no dish has a nonzero score, we return all dishes sorted by popularity (average rating).
  if (scoredDishes.isEmpty) {
    allDishes.sort((a, b) => b["average_underscore_rating"]
        .compareTo(a["average_underscore_rating"]));
    return allDishes;
  }

  // Otherwise, sort by highest match_score
  scoredDishes.sort((a, b) => b["match_score"].compareTo(a["match_score"]));
  return scoredDishes;
}

/// Sends the user query string to a FastAPI endpoint and retrieves
/// a JSON map that represents the structured query parameters.
Future<Map<String, dynamic>> sendQueryToFastAPI(String userQuery) async {
  final url = Uri.parse("http://127.0.0.1:8000/sendQuery");
  final headers = {"Content-Type": "application/json"};
  final body = jsonEncode({"user_query_str": userQuery});
  print("Sending query to FastAPI: $body");

  try {
    final response = await http.post(url, headers: headers, body: body);
    print("Received FastAPI response: ${response.body}");
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      print("FastAPI returned status code: ${response.statusCode}");
      return {}; // Return an empty map on error.
    }
  } catch (e) {
    print("Error sending query to FastAPI: $e");
    return {};
  }
}

/// Example function (placeholder) to upload data to Firestore
/// (not fully implemented in this code).
Future<void> uploadData() async {
  print("Data uploaded (dummy implementation).");
}

/// Main entry point of the Flutter app. Initializes Firebase,
/// then runs our [MyApp].
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  runApp(MyApp());
}

/// -------------------------------------------------------
/// MyApp: Root widget of the application.
/// Uses a Dark Theme, removes the debug banner.
/// -------------------------------------------------------
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firebase Upload & Filter Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        // Primary color
        primaryColor: Colors.deepPurpleAccent,
        // Default background color for scaffolds
        scaffoldBackgroundColor: const Color(0xFF121212),
        // Dark color scheme overrides
        colorScheme: const ColorScheme.dark(
          primary: Colors.deepPurpleAccent,
          secondary: Colors.deepPurple,
        ),
      ),
      home: HomePage(),
    );
  }
}

/// -------------------------------------------------------
/// HomePage
/// -------------------------------------------------------
/// - Displays a stylish header at the top
/// - Shows a list of recommended dishes (subcategories) as cards
/// - Allows user to type in a search query
/// - Sends query to FastAPI, gets structured parameters,
///   then fetches dishes from Firebase
/// - Renders subcategories with random prices
/// - Allows user to select items and "pay"
class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

/// _HomePageState:
/// - Maintains state for the search input, loading status,
///   and selected item indices
/// - Holds logic for fetching/filtering dishes
class _HomePageState extends State<HomePage> {
  /// Cache that stores the random prices for each (category, subcategory)
  /// so the same price remains consistent throughout the session.
  static final Map<String, int> _priceCache = {};

  /// Random instance to generate prices
  final Random _random = Random();

  /// List of filtered dishes
  List<Map<String, dynamic>> _filteredDishes = [];

  /// Whether data is currently being fetched
  bool _isLoading = false;

  /// Controller and focus node for the search bar
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  /// Whether the user is typing in the search bar
  bool _isTyping = false;

  /// Placeholder text to display when the search field is empty
  final String _searchPlaceholder = "Type something and I'll get it for you";

  /// Keeps track of the indices of selected dish cards
  Set<int> _selectedIndices = {};

  /// Flag to show a banner after successful payment
  bool _showBanner = false;

  @override
  void initState() {
    super.initState();

    // Listen for focus changes to update _isTyping
    _searchFocusNode.addListener(() {
      setState(() {
        _isTyping =
            _searchFocusNode.hasFocus && _searchController.text.isNotEmpty;
      });
    });

    // Listen for text changes to update _isTyping
    _searchController.addListener(() {
      setState(() {
        _isTyping =
            _searchController.text.isNotEmpty || _searchFocusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    // Clean up the controllers
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Sends the user input to FastAPI to get structured parameters,
  /// then fetches/filter dishes from Firebase using those parameters.
  void _filterDishes() async {
    setState(() {
      _isLoading = true;
    });

    final userQuery = _searchController.text;

    // Step 1: Send user query to FastAPI
    final fastAPIResult = await sendQueryToFastAPI(userQuery);
    print("FastAPI result received in _filterDishes: $fastAPIResult");

    // Step 2: Filter dishes in Firebase based on those query parameters
    final dishes = await getBestMatchingDishes(fastAPIResult);

    setState(() {
      _filteredDishes = dishes;
      _isLoading = false;
    });
  }

  /// Displays a payment success dialog. Once closed, clears everything,
  /// and shows a banner for 10 seconds.
  void _payAction() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Success"),
          content: const Text("Your payment was successful!"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("OK"),
            ),
          ],
        );
      },
    ).then((_) {
      setState(() {
        // Clear selection and search text, and refresh
        _selectedIndices.clear();
        _searchController.clear();
        _filteredDishes = [];
        _showBanner = true;
      });

      // Hide banner after 10 seconds
      Future.delayed(const Duration(seconds: 10), () {
        setState(() {
          _showBanner = false;
        });
      });
    });
  }

  /// Flattens the list of dishes so that each subcategory becomes its own card.
  /// Each subcategory gets (and keeps) a random price stored in _priceCache.
  List<Map<String, dynamic>> _flattenDishes(List<Map<String, dynamic>> dishes) {
    final List<Map<String, dynamic>> cards = [];

    for (var dish in dishes) {
      // Ensure category is lowercased and not null
      final category = dish["category"]?.toString()?.toLowerCase() ?? "";

      // If there are multiple subcategories in a list
      if (dish["subcategory"] is List) {
        // Special logic for milkshake: same price for all subcategories
        if (category == "milkshake") {
          // If not in cache, generate once for entire "milkshake" dish
          if (!_priceCache.containsKey("milkshake")) {
            _priceCache["milkshake"] =
                75 + (_random.nextInt(((150 - 75) ~/ 5) + 1)) * 5;
          }
          // Add each subcategory with the same cached price
          for (var sub in dish["subcategory"]) {
            cards.add({
              "category": dish["category"],
              "subcategory": sub,
              "price": _priceCache["milkshake"],
              "vendor": dish["vendor"],
              "taste": dish["taste"],
              "healthy": dish["healthy"],
              "dietary_restriction": dish["dietary_restriction"],
              "average_underscore_rating": dish["average_underscore_rating"],
            });
          }
        } else {
          // Otherwise, each subcategory gets its own cached price
          for (var sub in dish["subcategory"]) {
            final key = "$category::$sub";
            if (!_priceCache.containsKey(key)) {
              _priceCache[key] =
                  75 + (_random.nextInt(((150 - 75) ~/ 5) + 1)) * 5;
            }
            cards.add({
              "category": dish["category"],
              "subcategory": sub,
              "price": _priceCache[key],
              "vendor": dish["vendor"],
              "taste": dish["taste"],
              "healthy": dish["healthy"],
              "dietary_restriction": dish["dietary_restriction"],
              "average_underscore_rating": dish["average_underscore_rating"],
            });
          }
        }
      }
      // If there's just one subcategory (string) or it's null
      else {
        final sub = dish["subcategory"] ?? "";
        final key = "$category::$sub";

        if (!_priceCache.containsKey(key)) {
          _priceCache[key] = 75 + (_random.nextInt(((150 - 75) ~/ 5) + 1)) * 5;
        }

        cards.add({
          "category": dish["category"],
          "subcategory": sub,
          "price": _priceCache[key],
          "vendor": dish["vendor"],
          "taste": dish["taste"],
          "healthy": dish["healthy"],
          "dietary_restriction": dish["dietary_restriction"],
          "average_underscore_rating": dish["average_underscore_rating"],
        });
      }
    }

    return cards;
  }

  /// Returns the local asset path of an image for a given category.
  /// If category is not recognized, returns a placeholder path.
  String _getImagePath(String category) {
    switch (category.toLowerCase()) {
      case 'burger':
        return 'lib/pictures/burger.jpeg';
      case 'chai':
        return 'lib/pictures/chai.jpeg';
      case 'combo':
        return 'lib/pictures/combo.jpeg';
      case 'dessert':
        return 'lib/pictures/dessert.jpeg';
      case 'maggi':
        return 'lib/pictures/maggi.jpeg';
      case 'milkshake':
        return 'lib/pictures/milkshake.jpg';
      case 'pizza':
        return 'lib/pictures/pizza.jpg';
      default:
        // Fallback if file isn't found or category is unknown
        return 'lib/pictures/placeholder.png';
    }
  }

  /// Builds the search bar widget with a placeholder and a
  /// search or pay button (depending on item selection).
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Material(
        color: Colors.transparent,
        child: Row(
          children: [
            // Expanded TextField to capture user input
            Expanded(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey[900],
                      hintText: "",
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (value) {
                      // If user hits "enter" and nothing is selected, do the filter
                      if (_selectedIndices.isEmpty) {
                        _filterDishes();
                        setState(() => _isTyping = false);
                      }
                    },
                    onTap: () {
                      // On tap, mark that user is typing
                      setState(() => _isTyping = true);
                    },
                  ),
                  // If the user hasn't typed anything yet, show a placeholder
                  if (_searchController.text.isEmpty)
                    Positioned(
                      left: 16,
                      child: Text(
                        _searchPlaceholder,
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ),
                ],
              ),
            ),
            if (_isTyping || _selectedIndices.isNotEmpty)
              const SizedBox(width: 1),
            // Button changes based on whether items are selected
            if (_isTyping || _selectedIndices.isNotEmpty)
              ElevatedButton(
                onPressed: () {
                  if (_selectedIndices.isNotEmpty) {
                    // If items selected, proceed to pay
                    _payAction();
                  } else {
                    // Otherwise, search
                    FocusScope.of(context).unfocus();
                    _filterDishes();
                    setState(() => _isTyping = false);
                  }
                },
                child: Icon(
                  _selectedIndices.isNotEmpty ? Icons.payment : Icons.search,
                  color: Colors.white,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurpleAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Builds a card widget for each subcategory.
  /// Contains:
  ///  - An image (asset) with an [errorBuilder] fallback
  ///  - The subcategory and category text
  ///  - The price
  ///  - A checkmark if selected
  Widget _buildSubcategoryCard(Map<String, dynamic> cardData, int index) {
    final isSelected = _selectedIndices.contains(index);

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedIndices.remove(index);
          } else {
            _selectedIndices.add(index);
          }
        });
      },
      child: Stack(
        children: [
          Container(
            width: 160,
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Card(
              color: const Color(0xFF1E1E1E),
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Top image region
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        color: Colors.grey[800],
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: Image.asset(
                          _getImagePath(cardData["category"]),
                          fit: BoxFit.cover,
                          // If the image fails to load, show a placeholder icon
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.image,
                                size: 50,
                                color: Colors.white,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  // Bottom info (subcategory + price)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        Text(
                          "${cardData["subcategory"]}, ${cardData["category"]}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "₹${cardData["price"]}",
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[300],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Checkmark if selected
          if (isSelected)
            const Positioned(
              top: 8,
              left: 8,
              child: Icon(Icons.check_circle, color: Colors.green, size: 24),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check if we have any recommendations to show
    final hasRecommendations = _filteredDishes.isNotEmpty;

    // Flatten the filtered dishes so each subcategory is its own card
    final flattenedCards = hasRecommendations
        ? _flattenDishes(_filteredDishes)
        : <Map<String, dynamic>>[];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Stylish header with "BREEZ"
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: const Center(
                child: Text(
                  "BREEZ",
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 2,
                    shadows: [
                      Shadow(
                        offset: Offset(2, 2),
                        blurRadius: 4,
                        color: Colors.deepPurpleAccent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Banner after successful payment
            if (_showBanner)
              Container(
                width: double.infinity,
                color: Colors.grey[800],
                padding: const EdgeInsets.all(8),
                child: Center(
                  child: Text(
                    "Within 20 minutes your order will be ready",
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            // Use Spacer() to push content down
            const Spacer(),
            // If recommendations exist, show them in a horizontal list
            if (hasRecommendations)
              SizedBox(
                height: 250,
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: flattenedCards.length,
                        itemBuilder: (context, index) {
                          final cardData = flattenedCards[index];
                          return _buildSubcategoryCard(cardData, index);
                        },
                      ),
              ),
            // The search prompt bar
            _buildSearchBar(),
          ],
        ),
      ),
    );
  }
}
