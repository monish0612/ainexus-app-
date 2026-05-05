import { createBrowserRouter } from 'react-router';
import { RootLayout } from './components/RootLayout';

export const router = createBrowserRouter([
  {
    path: '/',
    Component: RootLayout,
  },
  {
    path: '/news',
    Component: RootLayout,
  },
  {
    path: '/tutor',
    Component: RootLayout,
  },
  {
    path: '/cloud',
    Component: RootLayout,
  },
]);
