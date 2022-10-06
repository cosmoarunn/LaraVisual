import { defineConfig } from 'vite';
import laravel from 'laravel-vite-plugin';

export default defineConfig({
    server: {
        port: 9000,
    },
    plugins: [
        laravel({
            input: ['resources/css/app.css', 'resources/js/app.js'],
            refresh: true,
        }),
    ],
    css: {
        preprocessorOptions: {
          scss: {
            additionalData: `
              @import "resources/scss/app.scss";
            `
          }
        }
    },
});
