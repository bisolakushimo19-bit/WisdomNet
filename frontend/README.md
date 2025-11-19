# WisdomNet Frontend

A modern, responsive React application for the WisdomNet prediction-assisted decision markets platform built on Stacks blockchain.

## Features

### 🎯 Core Functionality
- **Prediction Markets**: Create and participate in prediction markets
- **Decision Voting**: Vote on decisions with weight based on prediction accuracy
- **Real-time Updates**: Live market odds and voting results
- **Wallet Integration**: Seamless Stacks wallet connection via Hiro Wallet

### 🎨 UI/UX
- **Modern Design**: Clean, intuitive interface with Tailwind CSS
- **Responsive**: Mobile-first design that works on all devices
- **Dark Mode**: Eye-friendly dark theme
- **Interactive Charts**: Visual representation of market data using Recharts
- **Smooth Animations**: Polished user experience

### 🔒 Security
- **Wallet Authentication**: Secure connection to Stacks blockchain
- **Transaction Signing**: All transactions require user approval
- **Input Validation**: Client-side validation before blockchain interaction

## Tech Stack

- **React 18** - UI framework
- **TypeScript** - Type safety
- **Vite** - Build tool and dev server
- **Tailwind CSS** - Styling
- **@stacks/connect** - Wallet integration
- **@stacks/transactions** - Blockchain interactions
- **Lucide React** - Modern icon library
- **Recharts** - Data visualization

## Getting Started

### Installation

```bash
cd frontend
npm install
```

### Development

```bash
npm run dev
```

Visit `http://localhost:3000`

### Build

```bash
npm run build
```

### Preview Production Build

```bash
npm run preview
```

## Project Structure

```
frontend/
├── src/
│   ├── components/
│   │   ├── Header.tsx          # Navigation and wallet connection
│   │   ├── MarketCard.tsx      # Individual market display
│   │   ├── MarketList.tsx      # List of all markets
│   │   ├── CreateMarket.tsx    # Market creation form
│   │   ├── PlacePrediction.tsx # Prediction placement interface
│   │   ├── DecisionCard.tsx    # Decision voting card
│   │   ├── DecisionList.tsx    # List of decisions
│   │   ├── CreateDecision.tsx  # Decision creation form
│   │   ├── UserStats.tsx       # User statistics dashboard
│   │   └── MarketChart.tsx     # Market odds visualization
│   ├── hooks/
│   │   ├── useStacks.ts        # Stacks blockchain integration
│   │   └── useContract.ts      # Contract interaction logic
│   ├── utils/
│   │   ├── contract.ts         # Contract constants and helpers
│   │   └── format.ts           # Formatting utilities
│   ├── types/
│   │   └── index.ts            # TypeScript type definitions
│   ├── App.tsx                 # Main application component
│   ├── main.tsx                # Application entry point
│   └── index.css               # Global styles
├── public/                     # Static assets
├── index.html                  # HTML template
├── package.json                # Dependencies
├── vite.config.ts              # Vite configuration
├── tailwind.config.js          # Tailwind configuration
└── tsconfig.json               # TypeScript configuration
```

## Key Components

### Header
- Wallet connection button
- Network status indicator
- Navigation menu
- User balance display

### Market Components
- **MarketCard**: Displays market details, odds, and participation stats
- **MarketList**: Grid view of all active markets
- **CreateMarket**: Form to create new prediction markets
- **PlacePrediction**: Interface to place predictions with stake amount
- **MarketChart**: Visual representation of market odds over time

### Decision Components
- **DecisionCard**: Shows decision details and voting interface
- **DecisionList**: List of active decisions
- **CreateDecision**: Form to create new decisions
- **UserStats**: Dashboard showing user's prediction accuracy and voting weight

## Contract Integration

The frontend integrates with the WisdomNet smart contract deployed on Stacks blockchain:

### Contract Functions Used
- `create-prediction-market` - Create new markets
- `place-prediction` - Place predictions on markets
- `resolve-market` - Resolve market outcomes
- `create-decision` - Create new decisions
- `cast-vote` - Vote on decisions
- `claim-winnings` - Claim winnings from resolved markets
- `get-market` - Fetch market data
- `get-decision` - Fetch decision data
- `calculate-voting-weight` - Get user's voting power
- `get-market-odds` - Get current market odds

## Environment Variables

Create a `.env` file in the frontend directory:

```env
VITE_CONTRACT_ADDRESS=ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM
VITE_CONTRACT_NAME=WisdomNetcontract
VITE_NETWORK=testnet
```

## Styling

The application uses Tailwind CSS with a custom color palette:

- **Primary**: Blue shades for main actions
- **Success**: Green for positive outcomes
- **Warning**: Yellow for cautions
- **Danger**: Red for errors and negative outcomes
- **Neutral**: Gray scale for backgrounds and text

## Responsive Design

- **Mobile**: < 768px - Single column layout
- **Tablet**: 768px - 1024px - Two column layout
- **Desktop**: > 1024px - Three column layout with sidebar

## Performance Optimizations

- Code splitting with React.lazy()
- Memoization of expensive computations
- Debounced input handlers
- Optimized re-renders with React.memo()
- Lazy loading of images and charts

## Accessibility

- ARIA labels on interactive elements
- Keyboard navigation support
- Screen reader friendly
- High contrast mode support
- Focus indicators

## Browser Support

- Chrome/Edge (latest 2 versions)
- Firefox (latest 2 versions)
- Safari (latest 2 versions)
- Mobile browsers (iOS Safari, Chrome Mobile)

## Deployment

The frontend can be deployed to:
- **Vercel**: `vercel deploy`
- **Netlify**: `netlify deploy`
- **Render**: Static site deployment
- **GitHub Pages**: Via GitHub Actions

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

MIT License - see LICENSE file for details
