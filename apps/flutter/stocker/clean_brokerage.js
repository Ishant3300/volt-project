const fs = require('fs');
const path = './lib/views/create_user_view.dart';
let code = fs.readFileSync(path, 'utf8');

// Remove Map declaration
code = code.replace(/  \/\/ Brokerage settings per exchange[\s\S]*?_brokerageSettings = \{\};\n/g, '');

// Remove _brokerageSettings init
code = code.replace(/        \/\/ Initialize brokerage settings[\s\S]*?\}\n/g, '');

// Remove _fetchCurrentBrokerage call
code = code.replace(/      \/\/ Pre-fetch current brokerage values for display\n      _fetchCurrentBrokerage\(\);\n/g, '');

// Remove _fetchCurrentBrokerage function
code = code.replace(/  \/\/\/ Fetch current brokerage values[\s\S]*?\}\n/g, '');

// Remove _applyBrokerageSettings function
code = code.replace(/  \/\/\/ Apply brokerage settings[\s\S]*?(?=  @override)/g, '');

// Remove _buildBrokerageRow
code = code.replace(/  Widget _buildBrokerageRow[\s\S]*?(?=  Widget _sectionLabel)/g, '');

fs.writeFileSync(path, code);
console.log("Cleaned");
