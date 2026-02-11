import type { Config } from 'tailwindcss'

const config: Config = {
  content: [
    './src/pages/**/*.{js,ts,jsx,tsx,mdx}',
    './src/components/**/*.{js,ts,jsx,tsx,mdx}',
    './src/app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        primary: {
          50: '#f0f9ff',
          100: '#e0f2fe',
          200: '#bae6fd',
          300: '#7dd3fc',
          400: '#38bdf8',
          500: '#0ea5e9',
          600: '#0284c7',
          700: '#0369a1',
          800: '#075985',
          900: '#0c4a6e',
        },
        haven: {
          bg: '#121212',
          surface: '#1E1E1E',
          elevated: '#2A2A2A',
          border: '#333333',
          primary: '#6C63FF',
          active: '#4CAF50',
          warning: '#FFC107',
          error: '#EF4444',
          text: {
            primary: '#FFFFFF',
            secondary: '#B0B0B0',
            tertiary: '#707070',
          },
        },
      },
    },
  },
  plugins: [],
}
export default config
