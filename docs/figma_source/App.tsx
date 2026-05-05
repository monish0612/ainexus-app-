import { RouterProvider } from 'react-router';
import { router } from './routes';
import { SettingsProvider } from './utils/settingsContext';

export default function App() {
  return (
    <SettingsProvider>
      <RouterProvider router={router} />
    </SettingsProvider>
  );
}