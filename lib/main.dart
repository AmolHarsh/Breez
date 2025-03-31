import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

// -------------------------------------------------------
// Smart filter: fetch all dishes, score them based on query attributes,
// and return the best matching dishes.
// Now accepts a dynamic query map (from FastAPI) instead of hard-coded values.
Future<List<Map<String, dynamic>>> getBestMatchingDishes(
    Map<String, dynamic> query) async {
  print("Inside getBestMatchingDishes with query: $query");
  final db = FirebaseFirestore.instance;

  // Only consider non-null attributes for filtering
  final nonNullKeys = query.entries.where((e) => e.value != null).toList();

  // Fetch all dishes from Firestore
  final snapshot = await db.collection("dishes").get();
  final allDishes =
      snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();

  // Score and filter dishes based on matching non-null attributes.
  List<Map<String, dynamic>> scoredDishes = [];

  for (var dish in allDishes) {
    // Exclude dish if it has the dietary restriction mentioned in the query.
    if (query.containsKey("dietary_restrictions") &&
        query["dietary_restrictions"] is String &&
        dish["dietary_restrictions"] is String) {
      if (dish["dietary_restrictions"].toString().toLowerCase() ==
          query["dietary_restrictions"].toString().toLowerCase()) {
        continue; // Skip this dish.
      }
    }

    int score = 0;
    for (var entry in nonNullKeys) {
      String key = entry.key;
      dynamic queryValue = entry.value;
      dynamic dishValue = dish[key];

      // Special handling for dietary_restrictions if both are lists.
      if (key == 'dietary_restrictions' &&
          queryValue is List &&
          dishValue is List) {
        if (queryValue.any((element) => dishValue.contains(element))) {
          score += 1;
        }
      } else if (dishValue != null &&
          dishValue.toString().toLowerCase() ==
              queryValue.toString().toLowerCase()) {
        score += 1;
      }
    }
    if (score > 0) {
      dish["match_score"] = score;
      scoredDishes.add(dish);
    }
  }

  // If no dish has a nonzero score, fall back to the most popular dishes
  // sorted by average_underscore_rating.
  if (scoredDishes.isEmpty) {
    allDishes.sort((a, b) => b["average_underscore_rating"]
        .compareTo(a["average_underscore_rating"]));
    return allDishes;
  }

  // Otherwise, sort by highest match score and return those dishes.
  scoredDishes.sort((a, b) => b["match_score"].compareTo(a["match_score"]));
  return scoredDishes;
}

// Function to send the user query to FastAPI and receive the JSON output.
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

Future<void> uploadData() async {
  // Example function to upload data to Firestore (placeholder)
  print("Data uploaded (dummy implementation).");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  runApp(MyApp());
}

// -------------------------------------------------------
// Updated MyApp with a Dark Theme and debug banner removed.
// -------------------------------------------------------
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Firebase Upload & Filter Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.deepPurpleAccent,
        scaffoldBackgroundColor: Color(0xFF121212),
        colorScheme: ColorScheme.dark(
          primary: Colors.deepPurpleAccent,
          secondary: Colors.deepPurple,
        ),
      ),
      home: HomePage(),
    );
  }
}

// -------------------------------------------------------
// HomePage
// -------------------------------------------------------
class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

// _HomePageState now shows a stylish header at the top,
// displays recommendations as individual subcategory cards (flattened),
// each with a random price that stays consistent, and shows a loading indicator.
class _HomePageState extends State<HomePage> {
  // 1) Cache for storing the random prices so each (category, subcategory)
  //    keeps the same random price for the entire session.
  static Map<String, int> _priceCache = {};

  // For generating random prices
  final Random _random = Random();

  List<Map<String, dynamic>> _filteredDishes = [];
  bool _isLoading = false;

  // For the search bar
  TextEditingController _searchController = TextEditingController();
  FocusNode _searchFocusNode = FocusNode();
  bool _isTyping = false;

  // Static placeholder text
  final String _searchPlaceholder = "Type something and I'll get it for you";

  // Set to hold indices of selected dish cards.
  Set<int> _selectedIndices = {};

  // Banner flag after successful payment.
  bool _showBanner = false;

  // Trigger filtering by first sending the query to FastAPI and then searching Firebase.
  void _filterDishes() async {
    setState(() {
      _isLoading = true;
    });

    // Send user query to FastAPI
    String userQuery = _searchController.text;
    Map<String, dynamic> fastAPIResult = await sendQueryToFastAPI(userQuery);
    print("FastAPI result received in _filterDishes: $fastAPIResult");

    // Use the fastAPIResult as the query for Firebase filtering.
    List<Map<String, dynamic>> dishes =
        await getBestMatchingDishes(fastAPIResult);

    setState(() {
      _filteredDishes = dishes;
      _isLoading = false;
    });
  }

  // Payment action when items are selected.
  void _payAction() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Success"),
          content: Text("Your payment was successful!"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text("OK"),
            ),
          ],
        );
      },
    ).then((value) {
      setState(() {
        // Clear selection, search text, and refresh recommendations.
        _selectedIndices.clear();
        _searchController.clear();
        _filteredDishes = [];
        _showBanner = true;
      });
      // Hide banner after 10 seconds.
      Future.delayed(Duration(seconds: 10), () {
        setState(() {
          _showBanner = false;
        });
      });
    });
  }

  @override
  void initState() {
    super.initState();

    // Update _isTyping based on focus and text changes.
    _searchFocusNode.addListener(() {
      setState(() {
        _isTyping =
            _searchFocusNode.hasFocus && _searchController.text.isNotEmpty;
      });
    });
    _searchController.addListener(() {
      setState(() {
        _isTyping =
            _searchController.text.isNotEmpty || _searchFocusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // 2) This function flattens the dishes so that each subcategory becomes its own card.
  //    We store/retrieve the random price in _priceCache so it stays the same.
  List<Map<String, dynamic>> _flattenDishes(List<Map<String, dynamic>> dishes) {
    List<Map<String, dynamic>> cards = [];

    for (var dish in dishes) {
      String category = dish["category"]?.toString()?.toLowerCase() ?? "";

      if (dish["subcategory"] is List) {
        // Special logic for Milkshake: same price for all subcategories
        if (category == "milkshake") {
          // If not in cache, generate once for entire "milkshake" dish
          if (!_priceCache.containsKey("milkshake")) {
            _priceCache["milkshake"] =
                75 + (_random.nextInt(((150 - 75) ~/ 5) + 1)) * 5;
          }
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
          // For other categories, each subcategory gets its own cached price
          for (var sub in dish["subcategory"]) {
            String key = "$category::$sub";
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
      } else {
        // Single subcategory (string or null)
        String sub = dish["subcategory"] ?? "";
        String key = "$category::$sub";
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

  // 3) Helper to get the correct image path for a given category (lowercased).
  //    Adjust these extensions to match your actual file names.
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
        // Fallback if the file isn't found or the category is unknown
        return 'lib/pictures/placeholder.png';
    }
  }

  // Returns the search prompt widget.
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Material(
        color: Colors.transparent,
        child: Row(
          children: [
            // The TextField with a static placeholder overlay.
            Expanded(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey[900],
                      hintText: "",
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (value) {
                      if (_selectedIndices.isEmpty) {
                        _filterDishes();
                        setState(() => _isTyping = false);
                      }
                    },
                    onTap: () {
                      setState(() => _isTyping = true);
                    },
                  ),
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
            if (_isTyping || _selectedIndices.isNotEmpty) SizedBox(width: 1),
            if (_isTyping || _selectedIndices.isNotEmpty)
              ElevatedButton(
                onPressed: () {
                  if (_selectedIndices.isNotEmpty) {
                    _payAction();
                  } else {
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

  // 4) Builds a card for each flattened subcategory with an image background
  //    from lib/pictures/<category>.{jpeg/jpg}, and a checkmark if selected.
  //    We add an errorBuilder to fall back to an icon if the asset isn't found.
  Widget _buildSubcategoryCard(Map<String, dynamic> cardData, int index) {
    bool isSelected = _selectedIndices.contains(index);
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
            margin: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Card(
              color: Color(0xFF1E1E1E),
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(12)),
                        color: Colors.grey[800],
                      ),
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(12)),
                        child: Image.asset(
                          _getImagePath(cardData["category"]),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
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
                  // Subcategory + price
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        Text(
                          "${cardData["subcategory"]}, ${cardData["category"]}",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 4),
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
          if (isSelected)
            Positioned(
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
    bool hasRecommendations = _filteredDishes.isNotEmpty;
    // Flatten the filtered dishes so each subcategory becomes its own card.
    List<Map<String, dynamic>> flattenedCards =
        hasRecommendations ? _flattenDishes(_filteredDishes) : [];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Stylish header.
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Center(
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
            // Banner after successful payment.
            if (_showBanner)
              Container(
                width: double.infinity,
                color: Colors.grey[800],
                padding: EdgeInsets.all(8),
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
            Spacer(),
            // If recommendations exist, show the flattened subcategory cards.
            if (hasRecommendations)
              Container(
                height: 250,
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: flattenedCards.length,
                        itemBuilder: (context, index) {
                          var cardData = flattenedCards[index];
                          return _buildSubcategoryCard(cardData, index);
                        },
                      ),
              ),
            // The search prompt bar.
            _buildSearchBar(),
          ],
        ),
      ),
    );
  }
}
