import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// The JSON data converted into a Dart list of maps.
final List<Map<String, dynamic>> dishesData = [
  {
    "category": "Chai",
    "subcategory": [
      "Arunachali Chai",
      "Elaichi Chai",
      "Ginger Chai",
      "Masala Chai"
    ],
    "vendor": "Uncle Tony's",
    "taste": "Sweet",
    "size": ["Small", "Medium", "Large"],
    "healthy": "false",
    "price": "cheap",
    "dietary_restriction": "lactose intolerant",
    "average_underscore_rating": 4.2
  },
  {
    "category": "Cold Coffee",
    "subcategory": [
      "Plain Coffee",
      "Coffee with Ice Cream",
      "Hazelnut",
      "Blueberry Cold Coffee"
    ],
    "vendor": "Lounge1",
    "taste": "Sweet",
    "size": "",
    "healthy": "false",
    "price": "cheap",
    "dietary_restriction": "lactose intolerant",
    "average_underscore_rating": 3.8
  },
  {
    "category": "Milkshake",
    "subcategory": ["Vanilla", "Butterscotch", "Banana", "Blueberry"],
    "vendor": "Uncle Tony's",
    "taste": "Sweet",
    "size": "",
    "healthy": "true",
    "price": "medium",
    "dietary_restriction": "lactose intolerant",
    "average_underscore_rating": 4.5
  },
  {
    "category": "Burger",
    "subcategory": [
      "Veg Burger",
      "Cheese Burger",
      "Veg Cheese Burger",
      "Veg Paneer Burger",
      "Chicken Burger"
    ],
    "vendor": "Lounge1",
    "taste": "savory",
    "size": "",
    "healthy": "false",
    "price": "medium",
    "dietary_restriction": "",
    "average_underscore_rating": 3.7
  },
  {
    "category": "Patty",
    "subcategory": ["Aloo", "Vegetable", "Cheese", "Corn", "Paneer"],
    "vendor": "Uncle Tony's",
    "taste": "Umami",
    "size": "",
    "healthy": "false",
    "price": "medium",
    "dietary_restriction": "",
    "average_underscore_rating": 4.0
  },
  {
    "category": "Sandwiches",
    "subcategory": [
      "Cold",
      "Vegetable",
      "Tandoori",
      "Chicken Mayo",
      "Corn Mayo",
      "Cheese Corn",
      "Clubs"
    ],
    "vendor": "Lounge1",
    "taste": "Umami",
    "size": "",
    "healthy": "",
    "price": "medium",
    "dietary_restriction": "",
    "average_underscore_rating": 3.9
  },
  {
    "category": "Hot Coffee",
    "subcategory": ["Normal", "Black", "Hazelnut", "Strong", "Choco"],
    "vendor": "Uncle Tony's",
    "taste": "",
    "size": ["Small", "Medium", "Large"],
    "healthy": "",
    "price": "cheap",
    "dietary_restriction": "",
    "average_underscore_rating": 3.6
  },
  {
    "category": "Lassi",
    "subcategory": ["Mango", "Strawberry"],
    "vendor": "Lounge1",
    "taste": "Sweet",
    "size": "",
    "healthy": "",
    "price": "medium",
    "dietary_restriction": "lactose intolerant",
    "average_underscore_rating": 4.1
  },
  {
    "category": "Pizza",
    "subcategory": [
      "Double Cheese Pizza",
      "Garden Pizza",
      "Veg Level Pizza",
      "Paneer Pizza"
    ],
    "vendor": "Uncle Tony's",
    "taste": "Umami",
    "size": "",
    "healthy": "",
    "price": "medium",
    "dietary_restriction": "",
    "average_underscore_rating": 4.3
  },
  {
    "category": "All-Day Dining",
    "subcategory": [
      "Aloo Paratha",
      "Onion Paratha",
      "Mixed Paratha",
      "Paneer Paratha",
      "Chole Bhature",
      "Bread Omelette",
      "Boiled Eggs",
      "Plain Paratha",
      "Roti"
    ],
    "vendor": "Lounge1",
    "taste": "Umami",
    "size": "",
    "healthy": "",
    "price": "medium",
    "dietary_restriction": "",
    "average_underscore_rating": 3.5
  },
  {
    "category": "Thali",
    "subcategory": ["Veg Thali", "Non-Veg Thali"],
    "vendor": "Uncle Tony's",
    "taste": "",
    "size": "",
    "healthy": "",
    "price": "medium",
    "dietary_restriction": "",
    "average_underscore_rating": 4.0
  },
  {
    "category": "Juice",
    "subcategory": ["Orange Juice", "Apple Juice", "Mixed Fruit Juice"],
    "vendor": "Lounge1",
    "taste": "Sweet",
    "size": "",
    "healthy": "true",
    "price": "cheap",
    "dietary_restriction": "",
    "average_underscore_rating": 4.4
  },
  {
    "category": "Juice",
    "subcategory": ["Watermelon Juice"],
    "vendor": "Lounge1",
    "taste": "Sweet",
    "size": "",
    "healthy": "true",
    "price": "medium",
    "dietary_restriction": "",
    "average_underscore_rating": 3.8
  },
  {
    "category": "Maggie",
    "subcategory": ["Masala Maggie", "Cheese Maggie", "Vegetable Maggie"],
    "vendor": "Lounge1",
    "taste": "real",
    "size": "solid",
    "healthy": "false",
    "price": "cheap",
    "dietary_restriction": "",
    "average_underscore_rating": 3.9
  },
  {
    "category": "Milkshake",
    "subcategory": ["Oreo Shake"],
    "vendor": "Uncle Tony's",
    "taste": "Sweet",
    "size": ["Small", "Medium", "Large"],
    "healthy": "true",
    "price": "medium",
    "dietary_restriction": "lactose intolerant",
    "average_underscore_rating": 4.6
  }
];

class UploadDishesScreen extends StatefulWidget {
  @override
  _UploadDishesScreenState createState() => _UploadDishesScreenState();
}

class _UploadDishesScreenState extends State<UploadDishesScreen> {
  bool _isUploading = false;

  // Uploads each dish as a document in the "dishes" collection with document IDs "dish_001", "dish_002", etc.
  Future<void> uploadDishes() async {
    setState(() {
      _isUploading = true;
    });
    final firestore = FirebaseFirestore.instance;
    int index = 1;
    for (var dish in dishesData) {
      String docId = "dish_" + index.toString().padLeft(3, '0');
      print("Uploading $docId: $dish");
      await firestore.collection("dishes").doc(docId).set(dish);
      index++;
    }
    setState(() {
      _isUploading = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Data uploaded successfully")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Upload Dishes"),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: _isUploading ? null : uploadDishes,
          child: _isUploading
              ? CircularProgressIndicator(
                  color: Colors.white,
                )
              : Text("Upload Data"),
        ),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Firebase Upload Demo",
      home: UploadDishesScreen(),
    );
  }
}
